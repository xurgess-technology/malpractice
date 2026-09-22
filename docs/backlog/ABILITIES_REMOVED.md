# The ability system, as it was when it was removed

Brains and everything attached to them were deleted on the `brains-out` branch: the harvested brain
items and their spoilage, the break-room blender, and the two abilities the blender taught — **Echo**
and **Hive Eyes**.

The abilities went too because brains were the only way to earn them. They are expected back:
**grafting** is being built on another branch and will source ability levels instead of the blender.
`brains.gd`'s own comment said `add_ability()` / `set_level()` / `slot_of()` were kept deliberately
independent of *how* a level is earned, precisely so grafting could plug in later. That is the API
this file records, so it gets restored rather than reinvented.

**Removed in commit `REMOVAL_COMMIT`.** Everything below can be recovered verbatim with:

```
git show REMOVAL_COMMIT^:scripts/brains/brains.gd
git show REMOVAL_COMMIT^:scripts/brains/echo_view.gd
git show REMOVAL_COMMIT^:scripts/brains/hive_view.gd
git show REMOVAL_COMMIT^:scripts/brains/blender.gd
git show REMOVAL_COMMIT^:scripts/brains/brain_model.gd
git show REMOVAL_COMMIT^:scripts/hud.gd        # the circular ability hotbar
git show REMOVAL_COMMIT^:tools/braintest.gd    # the test that proved all of it
```

---

## The two abilities

| path | ability id | name | earned from |
|---|---|---|---|
| `"sonographer"` | `"echo"` | Echo | drinking a `brain_sonographer` |
| `"hive"` | `"hive_in"` | Hive Eyes | the `eye_hive` **graft** (the blender refused Hive brains) |

`PATHS` was `["hive", "sonographer"]` — the **order matters**, it indexes the points array.

```gdscript
const PATH_OF   := {"brain_hive": "hive", "brain_sonographer": "sonographer"}
const KIND_OF   := {"hive": "brain_hive", "sonographer": "brain_sonographer"}
const ABILITY_NAME       := {"hive": "Hive Eyes", "sonographer": "Echo"}
const ABILITY_ID         := {"sonographer": "echo", "hive": "hive_in"}
const ABILITY_ID_TO_PATH := {"echo": "sonographer", "hive_in": "hive"}
const MAX_SLOTS := 4
const MAX_LEVEL := 3
```

Note the asymmetry at the end: by the time it was deleted, Hive Eyes came **only** from grafting an
`eye_hive` (`scripts/grafting/grafts.gd`, `PART_ABILITY := {"eye_hive": "hive_in"}`), and the blender
refused Hive brains (`blendable()` returned false for `brain_hive`). Only Echo still came from a
brain. Whoever restores this should decide whether Echo also becomes a graft.

## The API grafting was meant to call

```gdscript
func points(peer_id: int, path: String) -> float
func level(peer_id: int, path: String) -> int          # mini(MAX_LEVEL, floor(points + 0.001))
func add_points(peer_id: int, path: String, amount: float) -> void
func slots_for(peer_id: int) -> Array                  # MAX_SLOTS entries, ability id or ""
func add_ability(peer_id: int, id: String) -> bool     # first empty slot; false if full; idempotent
func slot_of(peer_id: int, id: String) -> int          # slot index, or -1
func clear_ability(peer_id: int, id: String) -> void   # empties its slot AND zeroes its points
func set_level(peer_id: int, id: String, lvl: int) -> void  # direct; lvl >= 1 also grants the slot
func cooldown_left(peer_id: int, path: String) -> float
func ability_slot(p: Node, slot_idx: int) -> void      # host: the player pressed Alt+(slot_idx+1)
```

All host-authoritative. `set_level` / `clear_ability` were the two grafting already used:

```gdscript
# scripts/grafting/grafts.gd, as it was
game.brains.set_level(peer_id, String(PART_ABILITY[kind]), 1)   # graft installed
game.brains.clear_ability(peer_id, String(PART_ABILITY[had]))   # graft removed
```

**Slot assignment:** an ability entered the first empty slot the moment its path first reached level
1 — either through `add_points` crossing the boundary, or `set_level(.., >= 1)` directly. Nothing
ever re-packed the slots; `clear_ability` left a hole that the next new ability filled.

## Levels to effect values

Levels ran 0..3. Level 0 meant "not owned". The per-level curves were linear:

```gdscript
func echo_radius(lvl: int)  -> float: return 12.0 + 6.0  * lvl   # ECHO_RADIUS  + ECHO_RADIUS_PER_LEVEL
func echo_seconds(lvl: int) -> float: return 2.5  + 0.75 * lvl   # ECHO_SECONDS + ECHO_SECONDS_PER_LEVEL
func hive_range(lvl: int)   -> float: return 20.0 + 10.0 * lvl   # HIVE_RANGE   + HIVE_RANGE_PER_LEVEL
func hive_seconds(lvl: int) -> float: return 5.0  + 2.0  * lvl   # HIVE_SECONDS + HIVE_SECONDS_PER_LEVEL
```

Other tuning constants:

```gdscript
const ECHO_COOLDOWN := 20.0     # from the moment it fires
const ECHO_NOISE    := 1.2      # emit_noise(), so Echo is LOUD — it attracts monsters
const HIVE_COOLDOWN := 12.0     # counted from when the view ENDS, not when it starts
const HIVE_PRESS_GRACE := 0.5   # after a view ends, ignore that player's presses this long
```

**Points**, when they still came from the blender: a drink was worth 1.0 / 0.75 / 0.5 for a fresh /
spoiling / rotten brain, clamped to `MAX_LEVEL`, and stored as multiples of 0.25.

## What each ability actually did

- **Echo** — a shriek at the player. Emitted world noise (so monsters heard it), played
  `brains_shriek` on every machine, drew an expanding ring, and started `echo_view.gd`: an outline of
  everything within `echo_radius(lvl)` **through walls** for `echo_seconds(lvl)`.
- **Hive Eyes** — found the nearest non-sedated Hive monster within `hive_range(lvl)` (through
  walls), then rendered the game through a camera on that monster for `hive_seconds(lvl)`. The
  player's own body froze, head drooped, eyes glazed for teammates, and the mouse was taken away.
  Refused if the player was carrying something or operating. Ended early if the Hive died or was
  sedated, or if the player was hit, downed, stunned, grabbed or picked up. `HiveViewScript.FLIGHT_IN`
  was a fly-through whose duration was added to the authoritative end time.

## How it replicated

Host-authoritative throughout; clients only rendered.

- **Global snapshot field `br`** (`game.gd` `net_state()` / `apply_net_state()`), from
  `Brains.net_state()`, quantized:
  - `p`  — peer id -> `[hive points, sonographer points]`, snapped to 0.25
  - `hv` — peer id -> `[monster id, world_time the view ends]`, snapped to 0.1
  - `bh` — peer id -> blend progress 0..1, snapped to 0.05 (only while someone held E on the blender)
  - `ab` — peer id -> `Array[MAX_SLOTS]` of ability id, `""` for empty
- **Player report key `hv`** — `Player.hive_view: bool`, so every machine could pose a player who was
  away in a Hive.
- **Player input** — `ability_slot_press: Array = [0,0,0,0]`, a press counter per slot in the player
  report (indices 10..13 of the input array), dispatched host-side through
  `game.player_ability_slot(p, i)` -> `brains.ability_slot(p, i)`. Edge-detected against
  `_ability_slot_seen`, so a dropped packet could not lose a press.
- **Reliable events** — `br_echo` `{id, pos, r, s}`, `br_drink` `{id, kind, pos, cond}`,
  `br_hive` `{id, on}`. `br_hive` carried no state (the view followed `hv`); it existed only to keep
  the one-off moment ordered.
- **Nothing was ever saved.** Ability levels and absorbed brains lived only in memory and were wiped
  by `on_reset()` on game over, so no save file needs migrating.

## The input side

- Input action **`ability_alt`** in `project.godot`, rebindable as `key_ability_alt` in
  `scripts/settings.gd` (the settings screen row was labelled "Ability"). Holding it grew the four
  circular ability slots out of the item bar; **Alt+1..4** fired a slot.
- The HUD drew them in `scripts/hud.gd` `_draw_ability_bar()` with a procedural glyph per ability
  (`_draw_ability_icon`), a cooldown wedge, and a first-time "New ability" card. Icon art was
  `art/icons/hive_eyes.svg` and `art/icons/echolocation.svg`, coloured `#ff8a2a` (Hive Eyes) and
  `#9b6bff` (Echo) via `ItemIcons.ability(id)`.
- Esc during Hive Eyes called `Brains.local_exit()`, which just bumped that slot's press counter.

## Things that went with it, that a restore may want back

- `scripts/database/wall_pages.gd` had ability description pages in the database terminal, fed live
  from `hive_range` / `hive_seconds` / `echo_radius` / `echo_seconds` for the reader's current level.
- Database **tier 3** for a species was marked by `game.mark_db(path, "harvested", p)`, called **only**
  from the blender drink. With the blender gone nothing sets `harvested`, so tier 3 is currently
  unreachable. The field and the pages are still there; whatever replaces the blender should set it.
- The brain items themselves spoiled: full value for `FRESH_SECONDS` (45 s), then linearly down to
  `MIN_FACTOR` (0.15) at `ROTTEN_SECONDS` (225 s), carried on the item as `bt` (the world_time it was
  harvested). `scripts/grafting/eyes.gd` still has its own copy of that idea for eyes, which is a
  reasonable model to copy from.
