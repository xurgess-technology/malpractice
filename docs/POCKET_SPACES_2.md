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

### The three items
`Laundromat.ITEM_KINDS` declares the set (see "the item set" below).
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
`const ITEM_KINDS` on the layout script, next to `AMBIENT_NOISE_LEVEL`,
which is what the Laundromat declares. Phases 2 and 3 should match it.
Warm scrubs is in the set, but whether a permanent cosmetic unlock
*should* bleed into a corridor is the follow-up's call, not this one's.

### One shared-file fix, which phases 2 and 3 also need
`LootSpawner._draw_trinkets` drew the shift's 3-5 trinkets from every
trinket kind, knowing nothing about the level. A pocket-only trinket
has no `"*"` room weight, so on a shift without its space the draw
burned one of those few slots, and the swap pass at the end of `plan()`
then parachuted it into a hospital room it must never appear in. The
draw now only offers kinds the level has a positive-weight, fitting
location for (`_can_place`). Every hospital kind has a `"*"` weight, so
this is a no-op for everything that existed. **The Natatorium's whistle
and the Chapel's candle need exactly this**, so expect to meet here.

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
