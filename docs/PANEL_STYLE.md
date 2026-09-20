# The surgery panel

A testbed for a different way of presenting a surgery step. It exists on `main` alongside the old
work-plane steps; nothing else uses it yet, and **no phase of [SURGERY_OVERHAUL.md](SURGERY_OVERHAUL.md)
has been started**. Phase 3 waits on Zach playing this.

Built by `scripts/surgery/panel/surgery_panel.gd` (+ `panel_style.gd`), first used by
`scripts/surgery/games/suture.gd` on the test-only `laceration` procedure.

## What it is

When a player starts operating, a flat glowing **panel** pops in above the wound, facing the
leaned-in camera, and the step is played on it as an openly 2D diagram — X-ray board, Operation
board game. The real patient stays visible around the panel's edges and still reacts. When the
player steps away the panel disappears and nothing is left sitting on the body.

It is a real object in the room, not an overlay on your screen: a quad with an unshaded emissive
material fed by a SubViewport. Every machine builds its own copy, so onlookers see the panel and
its contents from their own angle, and a weak light tinted to the panel glows onto the patient and
the operator's hands.

## The rule

**THE PANEL IS THE INPUT SURFACE, THE BODY IS THE CONSEQUENCE SURFACE.**

Everything you aim at is on the diagram. Everything that happens because of it is on the patient:
the flinch, the blood on the gown, the monitor, the noise that draws monsters, and the scar they
walk out with. Nothing that is a *target* goes on the body, and nothing that is a *consequence*
stays on the panel after the step.

In particular: with nobody at the table there is nothing minigame-related on the patient at all.
The open laceration a player walks up to is the body's own overlay (`PatientKit.make_laceration`,
shown by `PatientBody._laceration` from the ailment and the case flags), not the step's.

## Placement and framing

- Anchored at the step's site marker, lifted `panel_lift` (0.24 m) along the site normal.
- Oriented **once**, at open time, to face the operator's final leaned-in camera pose, then frozen
  in the room (`top_level`). It is not a per-frame billboard: it is a fixed object you can walk
  round and look at from the side.
- 0.52 × 0.347 m (3:2), matching a 1200 × 800 SubViewport that only renders while the panel is open.
- It **stands up** rather than lying over the patient: the step's `camera_pose()` puts the operator
  well back (`view_tilt_deg`, 32 degrees off straight down) and the panel adds `tilt_bias_deg`
  (12 degrees) past facing them square on. Square on is easiest to play but nearly edge-on to
  everyone else in the room; the bias costs the operator nothing and gives onlookers a face to read.
- The step's `camera_pose()` is computed so the panel fills about 78% of the view's height at 16:9,
  which leaves the real patient, the table and the room visible around it.
- Render layer 20, the same one every minigame's props use, so the patient's blood decals (which
  project onto layer 1 only) never stamp across the diagram.
- Open: 0.2 s, scale 0.85 → 1.0 with a little overshoot, fading in. Close: 0.15 s. Both have
  `AudioStream` exports, empty for now.

### Getting out of the way

When something goes wrong the panel is the last thing you want to be looking at, so it clears:
`panel.ghost(seconds)` drops it to `ghost_alpha` (0.24) in `ghost_in` (0.09 s), holds, and brings it
back over `ghost_out` (0.45 s). You see the patient flinch, the blood spread on the gown and the
particles come off the body straight through the diagram, and then the diagram is back.

The suture step asks for it on a tear (0.55 s, so it is returning as the tear cooldown ends), on a
gush (0.9 s) and on a jerk from an underdosed patient (0.55 s). It is driven from `_react()`, which
runs on every machine from the replicated state, so onlookers see it clear too.

## Coordinates

A panel game works in **diagram millimetres**. The panel is a magnifier: `view_mm` (120 × 80 mm)
of diagram fits on the quad, so 1 mm is 10 px on the SubViewport.

- The panel plane replaces the work plane as the input surface: the mouse ray is projected onto it,
  `plane_extent()` is the panel's half-size in metres, and the game converts what `handle_cursor`
  gives it straight to millimetres with `panel.mm_of(p)`.
- Drawing goes the other way with `panel.mm_to_px(mm)` and `panel.mm_len_px(mm)`.
- A bot returns its cursor in the framework's units with `panel.metres_of(mm)`.

All of a panel game's tuning — wound sizes, tolerances, tool lag — is therefore in millimetres, and
none of it changes when the panel's physical size does.

## The style

Everything a panel draws with lives in `panel_style.gd`, so one file restyles every panel game.

- Background: near-black desaturated teal, with a thin bright rounded frame and corner ticks.
- A small header top-left (`LAC / CLOSE`) and the table number top-right.
- Flat shapes, 2–3 px outlines, soft glow only. **No skin shader, no textures, no attempt to blend
  with the body.**
- Palette: pale cyan / off-white outlines, red for danger and blood, green for good, amber for work
  that holds but is untidy, warm white for thread, pale steel for tools.
- **Readability beats atmosphere.** No scanlines, no noise, no grime — on purpose.

## How a new game opts in

The framework change is additive and opt-in; a step that does not override these behaves exactly as
it did before.

```gdscript
extends "res://scripts/surgery/minigame.gd"
const PanelScript := preload("res://scripts/surgery/panel/surgery_panel.gd")

var _panel: PanelScript = null

func setup(context: Dictionary) -> void:
    super.setup(context)
    _panel = PanelScript.new()
    _panel.header = "LAC / CLOSE"
    _panel.painter = _paint          # func(c: CanvasItem) -> void, draws in panel pixels
    add_child(_panel)                # a child of the minigame, i.e. at the site

func uses_panel() -> bool: return true
func plane_extent() -> Vector2: return _panel.half_size()
func input_plane() -> Transform3D: return _panel.input_plane()
func lamp_scale() -> float: return _panel.lamp_scale
func camera_pose() -> Dictionary: ...   # with "look": _panel.panel_lift, so the camera aims at the panel

func tick(delta: float) -> void:
    # The panel exists only while somebody is operating this table, on every machine.
    if bool(ctx.get("operating", false)) and not _panel.is_open():
        _panel.open(Vector3(0.0, pose.height, pose.back))
    _panel.tick(delta)
```

Three things the framework grew for this, all additive:

- `Minigame.uses_panel()` — false by default.
- `Minigame.input_plane()` — the node's own transform by default; a panel step returns its panel's
  plane, and the surgery system and the lab project the mouse onto that instead of the work plane.
- `camera_pose()` takes an optional `"look"`, metres along the plane's +Y to the point the camera
  aims at. 0 (the site itself) for every work-plane step; a panel step aims at its panel.
- `ctx["operating"]` — set by the surgery system every frame, true when *anyone* is operating this
  table. `ctx["operator"]` is only true on the operating machine, and a panel has to exist on every
  machine or onlookers do not see it.

## Seeing it

```bash
godot --path . tools/minigame_lab.tscn -- --game=suture --patient=bob --seed=3
```

`--cam=stand` (a player's eye height beside the table), `--cam=site` (straight down onto the site),
`--idle` (nobody operating: the panel stays shut) and `--marks=ggsgg` (a finished result on the
body) are all for judging what the panel and the body look like from outside the step.
`--selftest=suture` runs the headless checks.
