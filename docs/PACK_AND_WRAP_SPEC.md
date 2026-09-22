Addendum Two — Pack & Wrap (bleeder packing + bandage wrap)
Companion to the Anesthetic Injection handoff and the DODGE! addendum. Specifies step three of the gunshot wound: packing the bleeders, then wrapping the dressing. Both stages share the clipboard shell already specified — see that addendum for the frame, stamp cards, corner HUD and blood-splat system; this document covers what is new.

Source of truth: Gauze Pack and Wrap.dc.html · reference play space 960 × 600 px · September 2026

1 · Design direction
The brief's first pass reworked whack-a-mole and Snake into bespoke systems — timed soak-through, overlap rules, a kidney-dish aside — that added bookkeeping without adding a real decision. We went back to each genre's actual mechanic instead:

Whack-a-mole is one clean commit per target, on a timer you can't control. So WHACK! is that, with the "weight" of the pack expressed as a short hold instead of a click.
Snake is grow-by-eating, die-on-yourself. So WRAP! is that, with the pickup reframed as gauze and the trail reframed as bandage laid on the wound — no special-case rule for crossing your own trail.
The two stages run in sequence inside one step, WHACK! feeding WRAP!: how well the bleeders were packed determines how much of the wound comes into WRAP! already bleeding through, which needs a second bandage layer to fix. That's the one piece of cross-talk between them — everything else about each stage is that genre, honestly played.

2 · WHACK! — pack the bleeders
2.1 Setup
A top-down view of the wound tract across the page, drawn as the same flesh-red channel used in DODGE!, laid over bare skin. Bleeder count = 1 (the bullet bed itself) + one per tear carried over from DODGE! + zero or one seeded extra, clamped to 3–7 total. Bleeders are positioned along the tract at even intervals with jitter. The bed is visually larger and labeled.

2.2 Spurt cycle
Property	Rule
Spurt window	Each open bleeder spurts for 2.2 s (T), then cools 0.7–2.9 s (T) before spurting again. At most two bleeders spurt at once — the third-plus wait their turn. Only a spurting bleeder can be packed; the others are dormant blobs.
Packing	Point the mouse at a spurting bleeder and hold Space. A ring closes over 0.4 s (T, "packHold"); reaching full closes it permanently — one commit, no partial credit, no re-opening. Releasing early cancels with no penalty beyond the lost time; releasing while genuinely closed but on the wrong target (no bleeder under the cursor) bursts "TOO SOON!" as a tell, not a punishment.
Closed bleeder	Drawn as a pale disc with a stitched cross, permanently inert.
2.3 Blood loss, drawn as an event, not a fill
The original screen-filling column is cut — a full-screen tint doesn't localize the problem and never resolves, it just ends the level. Instead:

Loss meter ("BLOOD LOST %") only accumulates while at least one bleeder is actively spurting — rate 0.030 + 0.026 × (active count) per second (T, "bloodRate" multiplies both). Holding everything closed holds the meter, it does not just slow it.
Drips spawn from each spurting bleeder (~9/s chance-weighted) and fall down the page under gravity, landing as a blood-splat mark where they hit the bottom — the same randomized-splat system as the mistake feedback elsewhere, so the page gets visibly messier as a direct, local consequence of an open wound, not a screen-wide filter.
Escalating page splatter kicks in once loss passes 40%: one extra random splat per 10% band, three at a time past 80%. This is the "a lot of blood splatters the screen" behavior, arriving as a consequence of loss rather than a literal rising tide.
At 100% loss the stage ends (after a 1.1 s beat) regardless of remaining open bleeders; packing every bleeder also ends it early, cleanly.
2.4 Outcome
Pack quality = plugged ÷ total, carried into WRAP! as the fraction of wound cells that must take a second bandage layer (bleedCells). There is no separate WHACK! stamp card result — it flows straight into WRAP!'s opening card.

3 · WRAP! — bandage the wound
3.1 Board
A 16×10 grid, 52 px cells, drawn on bare skin. A flood-filled wound blob (~14 cells, 62% branch chance per neighbor from a random seed point) sits near the middle; a fraction of its cells equal to WHACK!'s loss (1 − packQ) are marked bleedCells and drawn with a ×2 tag — they need two bandage layers instead of one.

3.2 The roll is Snake, played straight
Property	Rule
Controls	WASD, true Snake steering (a queued turn can't reverse into the neck). Step rate 0.16 s/cell (T, "snakeRate"). This is the one place in the whole handoff that is not single-key — Snake's identity is grid steering, and forcing it onto one key would have broken the genre it's honoring.
The tail IS the gauze in hand	There is no separate "roll" counter drawn as a number tied to length. Tail length always equals cells carried: eating a gauze pickup lengthens the tail by one (adds a segment, "carry" +1); delivering a layer onto a wound cell shortens it by one immediately. An empty-handed head has no tail at all. This makes the state legible at a glance — a long tail is a full delivery queued up, a bare head means go fetch more.
Delivering	Driving onto a wound cell that still needs a layer, while carrying ≥1, consumes one carried unit and adds a layer to that cell (capped at its required count — 1 normally, 2 for a bleedCell). Driving onto a wound cell with nothing in hand does nothing — you cannot "wipe" coverage by passing over it empty.
Heading arrow	A small ink triangle on the head shows current travel direction, since the head is otherwise a plain square.
Death	Hitting a wall or any tail segment: −5 vitals, a TANGLE! burst, 2 blood splats, a shake. The roll respawns along the left edge carrying exactly what it was carrying at the moment of the crash (tail length = carry, unchanged) — a crash costs vitals and momentum, not your delivered progress or your queued gauze.
End condition	Every wound cell at its required layer count for 0.5 s → finish. There is no separate "roll ran out" fail state in this build; if you want one, gate total pickups spawned per run instead of a depleting counter, so it doesn't fight the tail-as-gauze legibility above.
4 · Results and carry-forward
One results card for the whole step, after WRAP! finishes: CLEAN / SLOPPY / MALPRACTICE stamp, plugged bleeders, pack quality %, wound coverage %, tangle count, vitals lost, one flavor line, Retry. Score = round(packQ×45 + coverage%×0.45 − tangles×6), clamped 0–100; grade bands CLEAN ≥80, SLOPPY ≥48, else MALPRACTICE.

Hand forward to the next step whatever quality signal it needs from this one — pack quality and final coverage are both already computed and are the natural inputs if infection risk or healing time are modeled downstream.

5 · Tuning knobs
bloodRate 1.0× (0.4–2) · packHold 0.4 s (0.15–1) · snakeRate 0.16 s/step (0.08–0.3) · initial gauze-in-hand 1. Keep these in the same tuning resource as the other two steps' knobs.
