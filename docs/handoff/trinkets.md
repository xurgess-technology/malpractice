# Handoff: `trinkets` (items and icons, chunk B)

Slot wt-2. Written 2026-09-18 at the wrap-up, before Zach has seen it.

The brief is [docs/ITEMS_AND_ICONS.md](../ITEMS_AND_ICONS.md), chunk B ("what the six trinkets do,
the scrap value when used up, the noises, networking"), plus Zach's own wording of each trinket.
The contract note is in docs/CONTRACTS.md, "Trinkets (docs/ITEMS_AND_ICONS.md chunk B)", and the
design is in DESIGN.md, Items › "Trinkets".

## What is done and working

Everything in the chunk B brief. The whole system is one new file,
`scripts/trinkets/trinkets.gd` (`Trinkets`), a child **"Trinkets"** of Game on every machine,
created in `_ready` beside Combat, Brains, Vats and Grafts.

- **The use path.** Left mouse with a trinket in hand goes through `Player._local_step` exactly
  where the saw and the needle do: `combat.is_usable(kind)` first, then
  `trinkets.local_try_use(p)`, and only if both refuse does the click become a shove. The clicking
  machine acts if it is the host and RPCs `_rpc_use` to the host if it is a client. No wind-up, no
  charge; at most one use per `USE_GAP` (0.25 s) per player, which is also what stops a duplicated
  RPC firing a trinket twice.
  **Note:** `Player.use_count` / `game.player_used` is a dead path on `main` (nothing bumps the
  counter any more, which is presumably why swallowing a placebo pill does nothing). I routed
  trinkets through `player_used` as well, so it works if that path is ever revived, but the live
  route is `local_try_use`.
- **Desk phone:** click sets it down at your feet as an ordinary world item and rings it for
  `RING_SECONDS` 10 s. Every `RING_PERIOD` 1.5 s the host emits a `"phone"` noise at
  `RING_LOUDNESS` 0.95 and, because the Hive is deaf, calls `alert_to` on every Hive within
  `RING_HIVE_RANGE` 14 m. Picking it up ends the ring and it is good as new. Selecting a desk phone
  rolls `PULL_RING_CHANCE` 12% to go off in your hands (the host watches every player's selected
  slot and rolls once per selection).
- **Laptop:** one charge. `hud.gd _draw_laptop_map` draws `MAP_SECONDS` 6 s of a north-up plan of
  the `MAP_RANGE` 25 m around you, built from `game.level_info.rows`, with an arrow for you, a
  sweep, and a blip for every surgery item in range (`trinkets.map_blips`). Then the battery dies.
- **Defibrillator:** aim at a downed teammate within `DEFIB_REACH` 2.6 m and they get up **where
  they lie** with `game.REVIVE_HP`; `revive_in_place` is `game.revive_player` without the scatter to
  the player table, and it sends the same `"revive"` event so every machine agrees. Bulky (two hand
  slots, already in the loot table) and `DEFIB_NOISE` 1.0 of noise, kind `"defib"`.
- **Pulse oximeter:** uses `combat.find_target` and `combat.can_sedate(m)`, so it is exactly the
  sedative jab's window (a monster stunned by a shove) and the Night Nurse is refused by
  `Monster.is_capturable`. On success the stack leaves your hands and the monster gets up and
  carries on. Every machine plays `trinkets_heartbeat` at the monster's position, at
  `BEAT_WANDER` 1.05 s / `BEAT_SUSPICIOUS` 0.62 s / `BEAT_HUNTING` 0.36 s from its replicated mode
  (`Trinkets.heart_mode` / `heartbeat_period`) -- positional and through walls, because a 3D audio
  player is not occluded. `trinkets.on_monster_removed`, called from `combat.on_monster_removed`
  (both `game.kill_monster` and strapping it to a table come through there), drops the pulse
  oximeter on the floor where the monster was, worth what it was worth.
- **Reflex hammer:** `HAMMER_REACH` 2.2 m, `HAMMER_COOLDOWN` 1.2 s, reusable. A teammate's view
  snaps 180 degrees (the new `Player.spin_view()`); a monster spins on the spot (the new
  **`Monster.spin_around()`**, host), and `HiveBrain.spun_around` forgets its target, stops seeing
  and starts searching where it now faces so the next sight check does not simply re-acquire you.
  The Night Nurse is refused before either.
- **EpiPen:** jab yourself or a teammate in front of you. `EPI_SECONDS` 10 s at
  `EPI_SPRINT_MULT` 2x sprint (the new `Player.sprint_mult`, pushed onto every player every
  physics frame from replicated state; stamina is held at 1 while it is up, or the boost would run
  out of breath after four seconds), then `EPI_COLLAPSE` 3 s of `p.stun`.
- **Used up.** `ONE_USE` (laptop, defibrillator, EpiPen) get `used: true` on the hand slot and their
  `v` drops to `SCRAP` ($8 / $15 / $3). The icon bar already greys and cracks a `used` slot
  (`hud.gd`, chunk C), the furnace already pays `s.v`, and the mark rides a drop as
  `WorldItem.x == "used"` (`game.pickup_item` turns it back into `used`), so a spent trinket stays
  spent for everyone. The phone, the hammer and the pulse oximeter are never spent.
- **Networking.** Host authoritative. The snapshot carries `g.tk`:
  `ri` ringing item ids, `rh` phones ringing in hands, `mp` live laptop maps, `tg`
  `{monster id: owner peer}`, `ep` EpiPen boosts, `sp` `{peer: spin counter}`. Rings and heartbeats
  are played by each machine from that plus the monster's replicated mode, so no sound crosses the
  wire. The reflex hammer's view snap is **a counter, not an event**: only the machine that owns a
  camera may turn it, and a counter cannot be lost or repeated by a dropped packet (the first value
  a machine ever sees is just remembered, so a late joiner does not spin on arrival).
- **Sounds:** `tools/gen_audio_trinkets.mjs` (`node tools/gen_audio_trinkets.mjs`) writes eight
  `audio/sfx/trinkets_*.wav`: `phone_ring`, `phone_pick`, `laptop_open`, `defib_zap`, `heartbeat`,
  `hammer_bonk`, `clip_on`, `epipen`. **I did not touch `tools/gen_audio.mjs`** -- docs/CONTRACTS.md
  "Ground rules" says to put new sounds in your own `gen_audio_<area>.mjs`, which contradicts the
  brief's "add them to gen_audio.mjs". Reconcile if Zach wants them in the one file.
- **Warmup:** nothing new to build, and `scripts/warmup.gd` says so where the loot models are made.
  The six are loot kinds, so their models, tinted stacks and icons (including the greyscale one the
  crack is drawn over) are already warmed; the laptop map is rects, circles, lines and text the HUD
  draws every frame anyway.
- **Docs:** DESIGN.md (Items, with a table of all six) and docs/CONTRACTS.md (the Trinkets section,
  the loot-table line, the review-setups list).

## Zach's review

```
tools\review.bat 2 "TRINKETS: try all six" --setup=trinkets --dev
```

`--setup=trinkets` (`scripts/review_setups.gd _trinkets`) drops straight into a solo shift on the
open floor beyond the OR: no phone call, no patient, no other monsters, no game over. The pulse
oximeter and the reflex hammer (the two reusable ones) are in your hands and the desk phone,
laptop, EpiPen and defibrillator lie in a row in front of you -- **two in hand, four on the floor,
because the bulky defibrillator needs two free slots and you only have four**. A Hive stands about
6 m ahead, calm for its first 12 seconds; Nurse Pratt (a dev dummy) lies downed beside you.
`-Count 2` opens a second window for a real teammate.

## Half-done, unsure, or worth a second opinion

- **The nettest covers the defibrillator, not the reflex hammer.** `trinkets` (2 clients) passes:
  client 1 shocks a downed client 2 awake over the wire, client 2 comes up **where it lay** on its
  own machine, and the used mark reaches client 1's own hands. I also wrote the hammer half (the
  host bonks client 1 and client 1's own camera snaps round) and **took it out again**: the spin
  demonstrably reaches the client -- I traced `spin_view()` running there and turning its heading
  from 0.08 to -3.06 rad -- but the bot-driven client's `rotation.y` was somehow back to its old
  value a few frames later while `bot_yaw` held the new one. That smells like something in the
  nettest harness or in `Player._local_step`'s bot path rather than this system, but I did not pin
  it down. **The turn itself is covered in `trinkettest`** (a teammate bonked on the host does spin
  180 degrees). Worth another look before anyone trusts the hammer in co-op.
- **The phone's decoy strength is a guess.** A ring is as loud as breaking glass (0.95) every 1.5 s
  and it also turns Hives within 14 m, which the Hive's "deaf" rule would not normally allow. Zach
  may want the Hives left out of it, or a shorter range.
- **12% on every pull-out may be a lot** if you switch slots often; the roll is per selection, so
  flicking 1-2-1-2 with a phone in hand rolls every time you land on it.
- **The laptop map is small** (268 px, top right) and north-up rather than view-up. It reads, but
  Zach may want it bigger, view-up, or with teammates on it.
- **The heartbeat has no distance cap of its own** beyond the audio bus's 30 m; a tagged monster on
  the far side of the hospital is simply inaudible. Nothing tells you *which* monster is tagged
  either, other than the line when it goes on.
- **Picking a ringing phone up ends the ring.** The alternative (it keeps ringing in your hands) is
  funnier and is one line; I went with the quiet one.
- **The defibrillator's cone is generous** (60 degrees, and anything within 1.6 m counts whichever
  way you face), because looking straight down at a body beside you is an awkward angle. That was a
  real finding from the nettest, not a test fudge.

## What I was about to do next

Open the review window and stop.

## Tests

Run one at a time in this checkout (`--fixed-fps 60`):

| Test | Result |
|---|---|
| `tools/trinkettest.tscn` (**new**) | **PASS** (58 checks, 0 failures) |
| nettest `trinkets` (**new**, 2 clients) | **PASS** |
| `tools/combattest.tscn` | **PASS** (0 failures) |
| `tools/downedtest.tscn` | **PASS** (0 failures) |
| `tools/monster_lab.tscn` | **PASS** (109 checks, 0 failed) |
| `tools/inventorytest.tscn` | **PASS** (98 checks, 0 failures) |

`tools/trinkettest.tscn` covers the brief's "Done when" list: each one-use trinket works once, is
greyed and cracked, refuses a second use and sells for its scrap value (and survives a drop and a
pick-up still spent); the desk phone rings, makes noise, can be picked up and used again, and its
pull-out roll lands at 12.4% over 4000 rolls (and about 11% over 200 real selections); the Night
Nurse refuses the clip, an unshoved Hive shrugs it off, a shoved one is tagged, the heartbeat
follows its mode, and the pulse oximeter comes back both when the monster is killed and when it is
caught; the reflex hammer spins a Hive 179 degrees, it loses sight of you and its next look does
not find you, it is refused inside its cooldown, a teammate's view snaps round, and the Night Nurse
ignores it.

Nothing in docs/FAILING_TESTS.md was touched or fixed. Not run: playtest shifts, doortest,
orscreentest, the rest of the nettest suite.

**Smoke look:** `tools/trinketshot.tscn` (**new**) boots the review setup and drives each trinket
once, writing `tools/trinket_shots/` (gitignored): the item bar, the laptop's map, the dead laptop
greyed and cracked, the phone set down, a teammate shocked back onto their feet, and a Hive before
and after a bonk (it is facing away, then facing you). Run it the way a review window runs:
`tools\review.bat 2 "SMOKE" -Scene res://tools/trinketshot.tscn --setup=trinkets`. Also
`-Scene res://tools/setupshot.tscn --setup=trinkets` for `tools/game_shots/setup_trinkets.png`.

## Known risks

- **`Monster.spin_around()` is new public monster surface** and `HiveBrain.spun_around()` is the
  only brain that reacts to it. A brain without one just gets the turn. The Sonographer is **not in
  the game yet** (`Monster.KINDS` is hive / discharged / night_nurse; its brain is chunk B of
  docs/SONOGRAPHER.md), so "a charging echo goes the wrong way" is not implemented -- but the hammer
  is generic, so it will turn a Sonographer the day one exists, and that brain can add
  `spun_around()` to do something better with it.
- **`Player.sprint_mult` is written every physics frame by this system** on every machine. Anything
  else that wants to scale sprint speed has to go through it or it will be stamped over.
- **The desk phone is placed with `game._spawn_item`**, so a phone set down in a doorway or on a
  stair can end up somewhere odd; it is an ordinary loose item after that.
- **A tagged monster's tag dies with the level** (`on_monsters_cleared`): clock out with a monster
  still wearing your pulse oximeter and it is gone. That matches "you get it back when it is caught
  or killed", but it is a way to lose one.
