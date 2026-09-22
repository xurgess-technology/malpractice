Addendum Three — SUTURE! (closing the wound)
Companion to the Anesthetic Injection handoff, the DODGE! addendum and the Pack & Wrap addendum. Specifies step four of the gunshot wound: running one continuous suture through the whole wound. The clipboard shell, stamp cards and blood-splat system are already specified in those documents; this covers what is new, plus a set of HUD changes that apply to all four minigames.

Source of truth: SUTURE.dc.html · reference play space 960 × 600 px · September 2026

1 · Design direction
The three earlier steps are all reflex games. This one is the pause: a single-path puzzle, played slowly and deliberately, where the failure state is your own untidiness rather than a timer beating you. It is LinkedIn's Zip, themed as suturing — one thread through numbered anchor points in order, visiting every open cell exactly once, never crossing itself.

Two decisions shape the feel. First, the wound closes as you work: each cell the thread enters is covered by skin with a seam line, and backing up reopens it. The puzzle state and the fiction are the same picture — you can read your progress by looking at how much gore is left, not at a counter. Second, time pressure is atmosphere, not a clock: the patient seeps slowly the whole time, but the rate is low enough that a careful 60-second solve is a good solve. Mistakes (pulling thread out) cost more than deliberation does.

2 · Two puzzles
Variant	Rule
Deep laceration	Open grid, no blocked cells. 4×4 on first play, stepping up to 5×5 once a laceration has been closed at CLEAN or SLOPPY. A long diagonal gash runs corner to corner under the grid.
Eye socket	6×6 with the centre 2×2 blocked by an eyeball — 32 open cells to thread around it. The wound is a torn orbit ringing the eye, with tears running outward.
The player picks the variant from a button under the board; it regenerates immediately. The grid always occupies the same 432 px square on the page — cell size, dot radius and numeral size all derive from it (cell = 432 ÷ n), so a 4×4 reads as large and roomy rather than as a small board on a big page.

3 · Generation — always solvable by construction
Never generate a puzzle and then test it. Generate the solution first and derive the puzzle from it:

Blocked cells first. Eye variant blocks the centre 2×2; laceration blocks nothing.
Hamiltonian path over the remaining cells: randomised depth-first search from a random start, backtracking, with neighbours ordered by fewest onward moves (Warnsdorff) plus a random tiebreak. Budget the search (≈120k node visits) and retry from a new start up to 12 times; in practice it lands first try. Measured cost: well under 5 ms per puzzle.
Numbers along that path. 1 at index 0, the last at the end, the rest at evenly spaced indices with ±1 jitter. Count = grid size (4 dots on 4×4, 5 on 5×5, 6 on 6×6). More numbers means an easier puzzle; this ratio gives a 20–40 s solve.
Walls last. Collect every adjacent open-cell pair whose shared edge the solution path never crosses, shuffle, take 0–4 of them (capped at n−2). Because they sit off the solution, the puzzle stays solvable by definition.
Verified over 40 generated puzzles: every one had a full-coverage solution respecting both number order and wall placement.

4 · Drawing the thread
Property	Rule
Start	Press on dot 1. Pressing anywhere else flashes that cell and does nothing.
Extending	While held, the pointer's cell is walked toward one orthogonal step at a time (up to 8 per event, so a fast drag doesn't skip cells). A step is legal if the cell is adjacent, unblocked, not already in the path, not behind a wall, and — if numbered — carries exactly the next number.
Undo	Pulling back onto the previous cell pops the head. Pressing directly on any earlier cell of the path unwinds to it in one gesture. Each popped segment: −1.6 vitals, a shake, one blood splat thrown off the field, and a TUGGED! burst every fifth pull.
Invalid move	Red cell flash (0.4 s) and a faint page tint. No vitals cost — an illegal move is information, not a punishment.
Win	Path length = open cell count and every number consumed in order. CLOSED! burst, the path resolves into perpendicular stitch ticks over ~1.1 s, then the report card.
Fail	Vitals reach 0 → FLATLINE!, 4 splats, hard shake, automatic MALPRACTICE.
The thread renders as a single ink line (4.5 px, hand-wobbled), with a needle glyph at the head and a dashed lead to the cursor while dragging. An earlier pass stacked a shadow, a core and a highlight; it read as clutter at this cell size. One line.

5 · Gore and closure
The wound matches what you are stitching. Laceration: a retracted skin lip, an open red channel and a near-black depth inside it, running the grid diagonal. Eye: the same three bands as a torn ring around the eyeball, with five ragged tears running outward.
Closure. Every cell the thread enters gets a skin patch drawn over the gore (irregular blob, ~0.62 cell radius, 0.16 s grow-in) with one faint seam line. Undo pops the patch and the gore returns. Draw order: wound → closures → grid and dots → thread.
Blood splats never land on the grid. Splat positions are rejection-sampled outside the board rectangle plus a 26 px margin. This matters: the board is the readable surface, and staining it hides the puzzle. Applies to seep splats, undo splats and flatline splats alike.
No ambient halftone. An earlier pass shaded the whole page with a distance-field dot screen. It was noise. The page is flat skin with the ink line work carrying the drawing.
The eye is fenced. A dashed surgeon's-marker rectangle inset in the 2×2, inward hatch ticks on all four edges, and a small "DO NOT STITCH" label. Bumping into it brightens the fence and hatching in addition to the normal cell flash.

6 · HUD and instructions — applies to all four minigames
The corner HUD from the earlier steps accumulated too much. Standardise on this:

Top-left, rules as bullets. Three short lines maximum, each with a small red bullet mark, stating what the player is trying to do — never how to press it. Here: follow the numbers in order · fill every open cell once · never cross your own thread.
Below them, keybindings as key caps. A visually distinct block: each binding is a boxed cap (pale fill, thin ink border, small-caps heading face) followed by an italic plain-language result. Here: LMB + PULL FORWARD — lay thread · LMB + PULL BACKWARD — undo a stitch · ESC — pull it all out. The boxes are the whole point: a player scanning the corner should be able to tell a rule from a button without reading.
Top-right, one number only. VITALS %, turning red under 35%. No monitor panel, no EKG trace, no run statistics — timing and stitch counts belong on the report card, not in play. The vitals beeper prototyped here was cut for this reason; do not reintroduce it in the other steps.

7 · Results and tuning
Report card: CLEAN / SLOPPY / MALPRACTICE stamp, closure time, stitches laid, thread pulled out, vitals lost, one flavor line, Retry. Score = round(100 − vitalsLost×1.1 − undos×2.2 − max(0, t−75)×0.3), clamped 0–100; CLEAN ≥78, SLOPPY ≥45, else MALPRACTICE. Note the shape of that formula: undoing is the expensive mistake, and the clock only bites after 75 seconds. A thoughtful player should never feel rushed into a wrong move.

Knobs: seepRate 1.0× of a 0.42 %/s base (0.3–2.5) · numberedDots 6 max, clamped to grid size (3–8) · wallCount 2 (0–4, capped at n−2) · mode eye | laceration · lacerationSize scaling | 4×4 | 5×5. Keep these alongside the other three steps' knobs. Debug build also carries a solution overlay (dashed green path), New puzzle, and Clear thread.

8 · Port notes
Nothing here needs a physics step or a frame-accurate update: the whole game is a cell grid, an ordered list of visited cells, and a slowly draining float. Model it as (a) a generator returning blocked set, solution path, number map and wall set; (b) an input handler that only ever appends or pops one cell; (c) a renderer reading that list. The animation clocks — closure grow-in, splat pop, stitch resolve, cell flash — are per-item timers, all under 1.7 s, and can be tweened by the engine rather than hand-integrated.

One thing to preserve in the port: the drag path is walked cell by cell, not snapped to wherever the cursor is. It is what makes a wall or the eye block feel like it physically stops the needle instead of teleporting the thread around it.
