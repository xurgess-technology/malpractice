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

## Phase 1 — system changes (first)
1. RECONCILE THE ROLL. PocketPlan rolls CHANCE = 0.5 flat; the design
   doc says higher odds in deeper wings. Make the code match the doc:
   low base chance scaling with wing depth, roughly 20-30% of shifts
   getting a pocket overall. Expose the curve as tunables.
2. NO REPEATS. Host tracks the last pocket kind seen this run and
   excludes it from the next roll.
3. AMBIENT NOISE FLOOR. Optional per-pocket field
   ambient_noise_level: raises the hearing threshold for
   sound-hunting monsters inside that pocket via the existing sound
   values. Factory and Restaurant set 0 (verify no behavior change).
4. FIX: monsters must not wander into pockets via random nav
   (KNOWN_ISSUES). Spawning inside and chasing through seams both
   stay. Fence idle wander at the stub; document the approach.
5. Seam light-mirroring and Hive-sight stay known issues; note they
   now apply to five spaces.

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
