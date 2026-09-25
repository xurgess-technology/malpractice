# The skill tree

The palm vein machine in Personnel reads your palm and draws your veins on its big screen: each
main vein is a specialty (a tree), each fork on it a skill, and the ones you have are filled with
blood. **Everything in it is a placeholder so far**: names, descriptions and costs, and no skill does
anything yet. The data model, the unlock flow, the saving and the question effects will ask are real.

## Using it

- Aim at the hand plate (or the screen) and press **E**. One surgeon at a time: anyone else gets
  "!Someone's palm is on the reader." (`Net.claim_station("veins")`, host-authoritative).
- You are stood at the plate and the camera glides from your eyes back to a view that fits the whole
  screen. The screen scans your hand (a scan line over a hand silhouette, the veins inside it lit as it
  passes), then the veins run up the fingers and out across the screen, forking into the skills
  (about 2 s of growth), and blood runs into the ones you own. A heartbeat pulses along the blood.
- Click a node to read it (the pick shows for everyone watching); **INFUSE** (or Enter) spends the
  points. **Esc**, **E** or a movement key steps away.
- Everyone in the room sees the same screen from where they stand: it is drawn on every machine from
  replicated state (who is at the reader, and their skills and pick).

## Points

**One skill point per shift you clock out of** (`Skills.POINTS_PER_SHIFT`, awarded in
`game.gd _set_phase` on SHIFT -> WON, on every machine for its own player; a late joiner still
waiting to spawn gets none). Money is the team's and resets on a wipe, so it is the wrong currency for
something that is yours for good. Costs are 1 to 3 points by depth.

## Saving

Like the monster database, every player keeps their own, on their own machine:
`user://skills.save`, plain JSON (`version`, `points`, `earned`, `unlocked`). It survives a wipe and a
restart. Machine runs (headless tests, `tools/*.tscn`) use `user://skills_machine.save`; a test that
wants its own file calls `Skills.use_path()`. Everyone else learns your skills through `Net.skills`
(replicated like `Net.looks`: a client tells the host, the host sends everyone the table). Co-op trust:
the host takes a client's word for its own skills.

## Files

| File | What |
| --- | --- |
| `scripts/skills/skill_tree.gd` (`SkillTree`) | The table: `TREES` (five, finger order) and `SKILLS`; rules (`unlock_problem`, `prereqs_met`, `depth`, `validate`) |
| `scripts/skills/skills.gd` (`Skills`) | This machine's points and skills, the save file, and the API below |
| `scripts/skills/vein_screen.gd` | The screen's picture: layout from the table, the timeline, hit testing |
| `scripts/personnel/vein_machine.gd` | The working machine: screen quad, plate glow, E target, the local session and camera |
| `scripts/net.gd` | `skills` / `set_my_skills` / `skills_for`, and the generic station lock `claim_station` / `release_station` / `station_user` |
| `tools/skilltest.tscn` | Headless checks (`-- --restart=write` then `-- --restart=read` for a two-process restart) |
| `tools/skillshot.ps1` | Minimized smoke-look shots into `tools/skill_shots/` |
| nettest `veins` | A client buys a skill, the host sees it, the other client is refused and watches |

Review: `tools\review.bat 1 "VEINS: ..." --setup=skill_tree` (`--fresh` forgets every skill first).

## API (for effects)

```gdscript
Skills.has_skill(peer_id, "surg_steady") -> bool   # any player: this machine's own, or Net's table
Skills.local_has("surg_steady") -> bool            # this machine's player
Skills.points, Skills.unlocked, Skills.earned
Skills.unlock(id) -> String                        # "" on success, else why not
Skills.award_shift() / grant(n) / top_up(n) / wipe()
```

## Adding a skill

1. Add an entry to `SkillTree.SKILLS`: `tree`, `name`, `desc`, `cost`, `requires` (ids in the same
   tree; several means all of them, drawn as veins that meet), and `at` (x: how far out along the
   tree's vein, 0 at the fingertip to 1 at the edge of the screen; y: how far to the side, -1 left
   to +1 right looking out along it).
2. Run `tools/skilltest.tscn`: it validates the table and checks every node is on the screen, clear
   of the panels and at least 64 px from any other. Take `tools\skillshot.ps1` and look.
3. Renaming a tree or skill is changing its `name`. Ids are what save files keep: an id only changes
   with a migration in `Skills._load` (unknown ids are dropped on load, unrefunded).

## Where effects hook in

Wherever the thing a skill changes is decided, ask `Skills.has_skill(peer_id, id)`. Host-side rules
(damage, sedation times, prices, spawn rolls) ask about the acting player's `peer_id`; client-side feel
(hand shake, prompts) can use `Skills.local_has`. Nothing calls either yet.
