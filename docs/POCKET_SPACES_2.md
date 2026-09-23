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

## Phase 3 — the Chapel
A hospital chapel that is somehow a cathedral: pews for three
hundred, vaulted dark ceiling, every votive candle lit, nobody who
lit them. Candlelight is the room's light.
- VOTIVE CANDLE: trinket, placeable light. Within its radius the
  Night Nurse counts as watched with no player looking. Burns out
  in ~2 minutes.
- COMMUNION WINE: anesthetic substitute, batch of 1, weak dose —
  shorter sedation, stirs sooner. Patients and strapped monsters.
- COLLECTION PLATE: loot, gold-watch tier.

## Phase 4 — the Laundromat
Coin-op, fluorescent, every machine running with nothing inside.
ambient_noise_level tuned so the drone genuinely masks footsteps
from the Sonographer — built entirely from the Phase 1 knob.
- BUCKET OF QUARTERS: loot; charged throw scatters a clattering
  handful as a directional noisemaker.
- WARM SCRUBS: cosmetics unlock pickup (scrub pattern for the
  personnel mirror). If the mirror isn't ready, bank the unlock in
  the host save and note it.
- FABRIC SOFTENER JUG: trinket. Drink it (E from hands): footsteps
  quieted ~60s (crouch noise multiplier at full speed). Sells as
  plain loot too.

## Phase 5 — items for the existing spaces — CODE DONE, TESTS UNFINISHED 2026-09-22, branch `pockets-phase5`
**Stopped early on purpose**, by Zach's call, because four slots had been
running Godot for hours and the machine had nothing left (an untouched
hospital corridor was benchmarking at 15 fps). All six items are built and
committed; what is missing is the test pass, not the work. **Read "What is
left" at the end of this section before picking it up.**

### What was built
Six items, three per space, plus one shared database tag.

**Factory** (`factory_floor`, `factory_office`, `factory_catwalk`):
- **COPPER WIRE SPOOL** — plain loot, `bulky`, tier 2, $55-95.
- **FOREMAN'S CLIPBOARD** — X-ray-film tier, $10-20. The struck-through rows
  are real geometry rather than a texture, because it is loot you are meant
  to stop and read.
- **GREASE BUCKET** — $15-28, and **deliberately still plain loot, not a
  trinket**. See the TODO below.

**Restaurant** (`restaurant`, `restaurant_kitchen`, `restaurant_restroom`):
- **CAST IRON MOLCAJETE** — gold-watch tier ($50-120), `bulky`. The only loot
  in the game made of rock.
- **TEQUILA, TOP SHELF** — batch of 1, weak dose. See "The tequila" below.
- **RESTAURANT PAGERS** — the pair. See "The pagers" below.

Every kind names only its own space's room kinds and **none lists `"*"`**, so
none of it can spawn in the hospital proper — the Natatorium's rule from
phase 2, followed exactly.

### POCKET_ITEMS: all four spaces now declare it
The Factory and the Restaurant had no items, so they had no list. They have
one now, in the same place and shape as the Natatorium's, which is what the
queued "items bleed out near the seam" task was waiting for:

    const POCKET_ITEMS := ["grease_bucket", "copper_wire_spool", "foremans_clipboard"]
    const POCKET_ITEMS := ["cast_iron_molcajete", "restaurant_pagers", "tequila"]

**`restaurant_pager` (singular) is deliberately absent from that list.** A
single pager is never placed on the map — it only ever comes out of a station
— so a task seeding hospital rooms from `POCKET_ITEMS` must not scatter
half-pairs around. The list is *what spawns here*, not *what exists here*.

### The pagers, and how the private buzz works over the wire
The spec's hard part is "a sound only its holder hears" in a co-op game.

**It is a replicated counter, not a targeted RPC.** `_buzz` is
`{peer: count mod 64}` and rides the existing `tk` snapshot as `pb`; every
machine receives it, and **each machine then decides for itself whether it is
the one that should render it**, which is true only where that peer is the
*local* player. Privacy is enforced at the render, not at the delivery. The
sound is played through `Audio.play` with **no position** (the 2D path), so it
is in that player's ears rather than in the room and cannot be overheard by
standing next to them, plus `CameraFX.add_shake(0.1, 0.35)`.

Why a counter and not `game._event.rpc_id(peer, ...)`, which exists and would
have been the obvious choice: this file's own contract says nothing
sound-related crosses the wire, and the reflex hammer's comment already argues
that **a counter cannot be lost or repeated by a dropped packet while a one-off
event can**. A communication device that silently drops messages is a broken
communication device. A machine seeing a counter for the first time records it
and does *not* fire, so a late joiner does not get buzzed on arrival.

A **planted** pager is the opposite and is the desk phone's exact plumbing: a
second counter `pr` keyed by world-item id, rendered **positionally by
everyone**, with the host emitting `PAGER_NOISE` (0.85) and hand-alerting the
deaf Hive within `PAGER_HIVE_RANGE`. 0.85 sits below the phone's 0.95 on
purpose — the phone costs you a whole item and shouts repeatedly, this is one
rattle you can fire again in `PAGER_COOLDOWN` (2.5 s) — but still above the
Sonographer's `LOUD` (0.8), so what hears it *comes*.

**The pair binding needed no new system.** The pair id lives in the stack's
`x`, the same small string that already carries a spent trinket's `used` mark
and a grafted eye's owner. `x` survives drop, throw, shelve, death-scatter and
pickup (game.gd writes it both ways, four sites) and is already replicated with
the world item. A table on `Trinkets` would have had to be taught all of that.

**"Selling either breaks the pair" is emergent, not a sell hook.** A pager asks
at the moment it is pressed whether anything else in the world still wears its
mark. Nothing does → it is a lone pager: no crosshair prompt, and
`local_try_use` returns **false** so the click falls through to a shove, which
is what "plain loot" has to mean mechanically. One rule covers selling, burning
in the furnace, and being left behind when the shift rebuilds — including ways
of breaking a pair nobody has thought of yet.

Using the station puts one pager in your hands and drops the other at your
feet, which is the item stating what it is for. The station's value is split
between the two, so taking the pair out neither mints nor burns money.

### The tequila, and the one number
`Syringes.FLUIDS` has listed `tequila` since the rack landed in 0.10.34, and
the rack populates itself from what you carry — so **the rack needed no change
at all**. What was missing was something to carry. Tequila is a loot kind
(room-weighted, which `Items.ITEMS` is not) with `consumable: true`; the only
supporting change was letting `LootTable.def` honour a per-kind `consumable`
flag instead of hard-coding `false`.

The weak dose is **one multiply**, in `inject_arcade._complete`, on the
finished sedation and nowhere else — the aiming, the band, the bubbles and the
scoring are untouched, so the game you play is identical and only what it buys
you is smaller. `Syringes.FLUID_POTENCY` is `0.7` for both alcohols.

**0.7 was chosen against an existing threshold, not for feel**: `SurgerySystem`
stirs a patient whenever sedation is under **0.75**, and harder the further
under. So a flawless shot of anesthetic is 1.0 and lies still; a flawless shot
of tequila is 0.70 — *just* under the line, so it stirs, but only just, and a
sloppy one falls away fast. That is exactly "shorter sedation, stirs sooner",
riding plumbing that already existed. The same number is right for phase 3's
communion wine, which the spec gives the identical rule.

### The "lure" tag, and the one line left open
`wall_pages.gd` had no tag system, so phase 5 added a small one: `TAG_TEXT`,
`ITEM_TAGS`, `tags_for()` and `kinds_tagged()`. A tagged item's database entry
prints its tag line and **names the rest of the family**, so the lures read as
one idea rather than three coincidences in three pocket spaces.

`lure` is applied to the **lifeguard whistle** and the **planted pager**.
**The bucket of quarters is NOT tagged**, because the Laundromat (phase 4) was
still being built in parallel and was not on `main` — its kind name is
deliberately not guessed at. **Whoever merges the Laundromat adds one line to
`ITEM_TAGS` in `scripts/database/wall_pages.gd`.** That is the only
cross-phase loose end.

### The grease bucket TODO (unchanged, and still blocked)
The slip patch needs a slide/knockdown state for monsters and players, which
the game does not have. Shipping it in `Trinkets.KINDS` with nothing behind the
click would swallow the shove and do nothing, so it **spawns and sells today**
and is plain loot. The day those states land: add it to `KINDS` and `ONE_USE`,
set `"trinket": true` with a `trinket_weight` in `loot_table.gd`, and write
`_use_grease`. The instructions are also written at the entry itself.

### What phase 5 was tested with — INCOMPLETE
- **`tools/mapcheck.gd`**, 12 seeds forcing the factory: **99.7% pocket nav,
  every entrance walks out through its seam**, and the only failures are the
  pre-existing morgue-tray ones (FAILING_TESTS 2) on **seeds 1 and 3** — which
  is exactly the pair that section predicts for a pocket-forced run. Clean.
- **`tools/trinkettest.tscn`**: **PASS, 0 failures**, run after the pagers
  landed. Note this proves the pagers **parse, load and do not disturb the
  other seven trinkets** — it does **not** yet exercise them, because no pager
  section has been written (see below).
- **`tools/pockettest.tscn`**: the **baseline before any change** was
  **FAILED 4 of 328**, all four the known FAILING_TESTS **1f** Night Nurse
  checks (restaurant and natatorium; the factory runs first and passes, which
  is precisely 1f's run-order pattern). `--only=factory` after the Factory
  items: **PASS, 104 checks**. **Not re-run after the Restaurant items.**
- **`tools/perfprobe` was not run**, and deliberately. Phase 5 adds no
  geometry, no lights and no materials to any space — it adds item kinds, whose
  models are primitives built by the same code path as every other loot kind.
  There is nothing here that can move a frame-time percentile. It would also
  have been worthless: the machine was running four slots and an untouched
  hospital corridor was measuring 15 fps, which is the contention phase 2 wrote
  its whole caveat about.

### What is left
1. **Run `pockettest` and compare against the 4/328 baseline above.** Phase 5
   added a `_check_pocket_items()` section to `tools/pockettest.gd` that runs
   once for all spaces: every space declares a non-empty `POCKET_ITEMS`, every
   kind in it is a real loot kind whose `rooms` name only that space's own room
   kinds and never `"*"`, no two spaces claim the same kind, and — the other
   way round — any loot kind whose rooms are wholly one pocket's **must** be in
   that pocket's list, so the lists cannot silently drift. **This has never
   been executed.** It is new code and may well have bugs.
2. **Write the pager section for `trinkettest.gd`.** Nothing yet exercises the
   pairing. What it should check: the station splits into two marked pagers
   whose values sum to the station's; pressing one raises the *other* peer's
   `pb` and not the presser's; a dropped partner raises `pr` and emits a noise
   at `PAGER_NOISE` instead; the cooldown refuses a second press inside
   `PAGER_COOLDOWN`; a pager whose partner has been destroyed reports
   `pager_alone` and `local_try_use` returns false; and the mark survives a
   drop and a pickup. `last_result` is already populated for all of these.
3. **A `syringetest` run**, since `inject_arcade` and `LootTable.def` were
   touched. The potency multiply is one line, but it is on the path every
   injection takes.
4. **docs/CONTRACTS.md is NOT updated.** The Trinkets section (search
   "### Trinkets") needs the pagers: the two new snapshot keys `pb` and `pr`,
   `PAIR_MARK` in `x`, and the two new sounds. The syringe section needs
   `FLUID_POTENCY`. This is the largest doc debt phase 5 leaves.
5. **Nobody has looked at any of this in a running game.** No review window was
   opened, so the icons, the models and the pager's shake are all unseen.

### The original brief
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
  the tuned threshold, heard outside.
- Night Nurse: frozen in a placed candle radius with no player
  looking; moves when it burns out.
- Onlooker: the monster_lab scenarios above.
- tools/gameshot shots of each space, each seam from the hallway
  side, and the Onlooker mid-stare in the Factory fog.
- docs/MORNING_REPORT.md with START HERE, judgment calls, skips.
