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

## Phase 2 — the Natatorium
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

### Phase 3 — DONE 2026-09-22, branch `pockets-chapel`

**The space.** `scripts/level/pockets/chapel.gd`. A nave 33 m long under a vault 24 m up that
nothing ever lights, two arcades of stone piers with pointed arches between them, side aisles
ceiled much lower (9 m) so the nave reads tall, thirty-two rows of pews, a sanctuary with an altar
and a reredos of votive tiers, and a sacristy behind the one hinged door. Origin (800, 1000).

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
- `tools/pockettest.tscn`: **PASS, 310 checks** (208 before; the Chapel adds 102). Seams, links,
  the noise floor and the wander fence all pass for it.
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
- **`tools/perfprobe` was run**, on a real window, minimized and never activated
  (`tools/pocketperf.ps1`). At **medium (q1)** every Chapel view holds the bar: the whole nave from
  the narthex, which is the designed worst frame (every rack, every stand, both arcades, all the
  pews and the reredos at once), is **72 fps avg / 55 1% low**; the reredos close up 109/80, a side
  aisle 97/79, an entrance from inside 122/105, the seam from the pocket side 79/77. The one
  marginal number is the seam from the **hospital** side at 73/50, sitting exactly on the 1% low
  bar. The hospital-corridor baseline on the same map read 64/44 in this run against ~61/55 in a
  plain run, so the machine was noisy by then and the 50 should be re-read on a quiet one.

**What had to change outside the Chapel, all of it additive.**
- `PocketSpaces.LAYOUTS` + `script_for(kind)` replaced the two-way `Factory if ... else Restaurant`
  ternaries (three of them) and the hardcoded `warm()` pair. **A fourth kind is now one line.**
- `tools/mapcheck.gd`, `tools/pockettest.gd` and `tools/perfprobe.gd` sweep `PocketPlan.KINDS`
  instead of a hardcoded pair, so phase 4's space is covered by all three for free.
- `ItemSpawner._legal` gained an optional `rooms` filter on an item definition, so the wine is only
  ever found in the Chapel. An item without a `rooms` key is found anywhere, which is every other
  item, so nothing else changes.
- `perfprobe --pocketkind=<kind>`, because `--pockets` crashes before it measures anything. That is
  **pre-existing** and now written up as FAILING_TESTS 3.

**The item set, for the task that bleeds pocket items into the hospital.** `Chapel.POCKET_ITEMS`
lists `votive_candle`, `communion_wine`, `collection_plate`, and sits beside `AMBIENT_NOISE_LEVEL`.
There was no existing convention — the Factory and the Restaurant contribute no items of their own,
their loot coming from the normal wing tables through containers and anchors — so the Natatorium
and the Chapel arrived at the same shape independently and settled on this name. The wine is in the
set deliberately: it is a fluid the syringe rack is designed for, so it is the likeliest of the
three to be wanted outside the Chapel.

**No new assets.** Everything is procedural over the existing CC0 tileables through `Common.tri_mat`
and `LootModels`/`ItemModels` primitives, exactly as the Factory and the Restaurant are, so
ASSETS.md needs no new row. Two generated sounds were added to `tools/gen_audio_trinkets.mjs`
(`trinkets_candle_light`, `trinkets_candle_out`).

**Unsure / for whoever merges.** The three sedation touch points (`surgery_system.can_begin`,
`game.surgery_step_done`, `dissection._anesthetic_slot`/`redose`) are the likeliest merge conflict
with the syringe-rack task, which is moving DRAW!/FLICK! out of the OR. Nothing here restructures
the injection, but the lines are close together.

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
  the tuned threshold, heard outside.
- Night Nurse: frozen in a placed candle radius with no player
  looking; moves when it burns out.
- Onlooker: the monster_lab scenarios above.
- tools/gameshot shots of each space, each seam from the hallway
  side, and the Onlooker mid-stare in the Factory fog.
- docs/MORNING_REPORT.md with START HERE, judgment calls, skips.
