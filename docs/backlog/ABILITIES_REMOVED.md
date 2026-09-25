# What brains took with them, and what came back

Brains were removed on the `brains-out` branch: the harvested brain items and their spoilage, the
break-room blender, the dumpster price, and everything that fed on them.

The two **abilities** — Echo and Hive Eyes — were deleted along with them at first, because the
blender was the only way to earn them. That was reversed the same day: **the abilities are back,
and only brains stayed gone.** This file is the record of what changed in between, and of the one
real hole the removal left.

The system now lives in `scripts/abilities/` (`abilities.gd`, `echo_view.gd`, `puppet_view.gd`) as
the `Abilities` child of Game, reached as `game.abilities`.

**2026-09-24: Hive Eyes is gone, replaced by Puppet** (same slot, key, cooldown and level structure,
same graft; you climb into the Hive and walk it about instead of only looking). Everything below
that described Hive Eyes' API now describes Puppet's; docs/CONTRACTS.md "Abilities" has the whole
thing.

---

## The one thing that actually changed: where a level comes from

Brains were the earning mechanic. With them gone:

- **Puppet (was Hive Eyes) is earned by grafting.** An `eye_hive` graft grants it at level 1, and
  taking the part out takes it away again (`scripts/grafting/grafts.gd`,
  `PART_ABILITY := {"eye_hive": "puppet"}`).
  That code already existed before any of this; it is now the *only* source of an ability in the
  game. This was always where it was heading — the old `brains.gd` comment said `add_ability()` /
  `set_level()` / `slot_of()` were kept deliberately independent of how a level is earned, precisely
  so grafting could plug in.
- **Echo has no source yet.** Drinking a Sonographer brain was the only one. Nothing grants `echo`
  in a normal shift now. It still works end to end — the dev panel, `set_level()` and the review
  setups all reach it — but **a player cannot currently earn Echo.** A known gap, not an oversight.

  It closes when **grafting part two** lands: `docs/GRAFTING_TRACHEA.md` is the Sonographer's
  trachea graft, whose payoff was always Echo. The brief is written and the art exists
  (`art/icons/items/sonographer_trachea.svg`); the code does not — `Eyes.KINDS` is still just
  `["eye_hive", "eye_surgeon"]`. It is being built on another machine, so **nothing was invented
  here to fill the hole.**

  When it lands, wiring Echo up is one line, beside the entry `eye_hive` already has:

  ```gdscript
  # scripts/grafting/grafts.gd
  const PART_ABILITY := {"eye_hive": "puppet", "trachea_sonographer": "echo"}
  ```

  `grafts.gd` is generic over part kinds on purpose — its own header says part two "slots in
  through `PART_ABILITY` and `Eyes.NOUN` without a rewrite" — so nothing else has to change.
- **Points are gone.** Levels used to be a float accumulated in multiples of 0.25, because a brain
  was worth 1.0 / 0.75 / 0.5 depending on how fresh it was. With the blender gone nothing produced a
  fraction, so `points()`, `add_points()`, `points_for()` and the `POINTS_FRESH` / `POINTS_SPOILING`
  / `POINTS_ROTTEN` constants went with it. **Levels are now plain ints, set directly.** Grafting
  only ever called `set_level()`, so nothing it depends on changed.

## The API, as it stands

All host-authoritative.

```gdscript
func level(peer_id: int, path: String) -> int               # 0..MAX_LEVEL
func slots_for(peer_id: int) -> Array                       # MAX_SLOTS entries, ability id or ""
func add_ability(peer_id: int, id: String) -> bool          # first empty slot; false if full; idempotent
func slot_of(peer_id: int, id: String) -> int               # slot index, or -1
func clear_ability(peer_id: int, id: String) -> void        # empties its slot AND zeroes its level
func set_level(peer_id: int, id: String, lvl: int) -> void  # lvl >= 1 also grants the slot
func cooldown_left(peer_id: int, path: String) -> float
func ability_slot(p: Node, slot_idx: int) -> void           # host: the player pressed Alt+(slot_idx+1)
```

The two grafting already uses:

```gdscript
game.abilities.set_level(peer_id, String(PART_ABILITY[kind]), 1)   # graft installed
game.abilities.clear_ability(peer_id, String(PART_ABILITY[had]))   # graft removed
```

**Slot assignment:** an ability enters the first empty slot the moment `set_level(.., >= 1)` grants
it. Nothing re-packs the slots; `clear_ability` leaves a hole that the next new ability fills.

## Ids, paths and levels

| path | ability id | name | source |
|---|---|---|---|
| `"hive"` | `"puppet"` | Puppet (was Hive Eyes, id `hive_in`) | the `eye_hive` graft |
| `"sonographer"` | `"echo"` | Echo | **nothing — see above** |

`PATHS` is `["hive", "sonographer"]`; the **order matters**, it indexes the level array.
`MAX_SLOTS` is 4, `MAX_LEVEL` is 3. Level 0 means "not owned".

```gdscript
func echo_radius(lvl: int)  -> float: return 12.0 + 6.0  * lvl
func echo_seconds(lvl: int) -> float: return 2.5  + 0.75 * lvl
func puppet_range(lvl: int)   -> float: return 20.0 + 10.0 * lvl
func puppet_seconds(lvl: int) -> float: return 3.0  + 1.0  * lvl   # after the 1 s fly-in

const ECHO_COOLDOWN := 20.0     # from the moment it fires
const ECHO_NOISE    := 1.2      # emit_noise(), so Echo is LOUD -- it attracts monsters
const PUPPET_COOLDOWN := 12.0     # counted from when you come BACK, not when it starts
const PUPPET_PRESS_GRACE := 0.5   # after it ends, ignore that player's presses this long
```

## How it replicates

- **Global snapshot field `ab`** (was `br`), from `Abilities.net_state()`:
  - `lv` — peer id -> `[hive level, sonographer level]` (ints)
  - `pp` (was `hv`) — peer id -> `[monster id, world_time it ends]`, snapped to 0.1
  - `sl` — peer id -> `Array[MAX_SLOTS]` of ability id, `""` for empty
- **Player report key `pp`** (was `hv`) — `Player.puppeting: bool`, so every machine can pose a player
  who is away in a Hive (head droops, eyes glaze for teammates) and so the grafted eye's glow matches.
  A puppeting client also sends `puppet_move` / `puppet_yaw` in its report_state (`[20]`, `[21]`).
- **Player input** — `ability_slot_press: Array = [0,0,0,0]`, a press counter per slot at indices
  10..13 of the report array, dispatched host-side through `game.player_ability_slot(p, i)`.
  Edge-detected against `_ability_slot_seen`, so a dropped packet cannot lose a press.
- **Reliable events** — `ab_echo` `{id, pos, r, s}` and `ab_puppet` `{id, on}` (were `br_echo` /
  `br_hive`, then `ab_hive`). `ab_puppet` carries no state (the view follows `pp`); it exists to keep the one-off
  moment ordered. `br_drink` is gone for good — it was the blender.
- **Nothing is saved.** Levels and slots live only in memory and are wiped by `on_reset()` on game
  over, at the same time as the grafts that grant them.

## Input and presentation

- Input action **`ability_alt`**, rebindable as `key_ability_alt` (the settings row is "Ability").
  Holding it grows the four circular slots out of the item bar; **Alt+1..4** fires a slot.
- `scripts/hud.gd` `_draw_ability_bar()` draws them, with a per-ability glyph, a cooldown wedge,
  level pips and a first-time "New ability" card. Icons are `art/icons/puppet.svg` and
  `art/icons/echolocation.svg`, coloured `#ff8a2a` and `#9b6bff` via `ItemIcons.ability(id)`.
- Esc while puppeting calls `Abilities.local_exit()`, which bumps that slot's press counter.
- Audio: `ability_shriek`, `ability_hive_in`, `ability_hive_out`, generated by
  `tools/gen_audio_abilities.mjs`. The blender's own cues (`brains_blend`, `brains_gulp`,
  `brains_squelch`) are gone.

---

## What brains took with them for good

Removed in commit `5397ddd`; recoverable with `git show 5397ddd^:<path>`.

- `scripts/brains/brains.gd` — the spoilage model, the blender, the drink, and the points system.
- `scripts/brains/blender.gd`, `scripts/brains/brain_model.gd`.
- The loot kinds `brain_hive` ($150) and `brain_sonographer` ($350), both tier 3 and never found by
  the loot spawner — they only ever existed as a harvest.
- **Spoilage:** a brain held full value for `FRESH_SECONDS` (45 s), then fell linearly to
  `MIN_FACTOR` (0.15) at `ROTTEN_SECONDS` (225 s), carried on the item as `bt` (the world_time it
  was harvested). `scripts/grafting/eyes.gd` has its own copy of the same idea for eyes, which is
  the model to crib from if anything needs to spoil again.
- `tools/braintest.gd` — the test that covered all of it, including the ability behaviour. Worth
  reading if ability coverage ever needs rebuilding.
- **Database tier 3 is now unreachable.** `game.mark_db(path, "harvested", p)` was called *only*
  from the blender drink. The `harvested` bit, the persisted field and the pages are all still
  there; nothing sets it any more. Whatever replaces the blender should.

### One thing that deliberately did NOT go

`WorldItem.bt` **stays.** It reads like a brains field and is documented as one, but grafting's vats
use the same key as the **eye** spoil clock (`vats.eye_value({"v": value, "bt": bt})`). Removing it
would have silently broken eye spoilage. It is now commented as the grafting field it actually is.

Likewise `spawn_hive(pos)` — a Hive *monster* spawner that merely lived on the brains node — moved
to `game.gd`, because a number of unrelated tests spawn a Hive with it.
