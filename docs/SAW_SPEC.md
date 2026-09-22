Addendum Four — SAW! (taking the limb off)
Companion to the Anesthetic Injection handoff and the DODGE!, Pack & Wrap and SUTURE! addenda. Specifies step five of the gunshot wound: amputation. The clipboard shell, stamp cards, comic bursts and blood-splat system are already specified in those documents; the HUD and keybinding standard set in the SUTURE! addendum applies here unchanged. This covers what is new.

Source of truth: SAW.dc.html · reference play space 960 × 600 px · September 2026

1 · Design direction
Pong, where the ball is a bone saw and the limb does not bounce it back. The arm lies across the table seen from above, running the full height of the court; the blade travels left to right through it. Paddles sit at both edges and are mirrored onto one input, so the player is not playing an opponent — they are keeping a tool in motion through a body.

The governing decision: the limb is destructible material, not a progress bar. Every cell of the arm holds a stack of layers, the blade strips one layer from whatever it physically passes over, and the amputation completes when a gap opens from one side of the limb to the other. Progress and picture are the same object — the player reads how far along they are by looking at how much arm is left, and a careless run leaves a visibly chewed stump rather than a lower number. Everything that once sat on top of that (marked zones, lane depths, stroke quotas, an artery, hard returns, a table-strike penalty) was tried and cut; they all replaced a thing the player could see with a rule they had to be told.

2 · The limb as material
The arm is a grid of cells — 40 across the limb's width by 100 down the court — each holding a depth counter that starts at the layer count N (default 4). A cell's appearance is a pure function of its remaining depth and whether its column falls inside a bone shaft:

Depth	Off a bone	On a bone
4 — intact	skin	skin
3	meat	meat
2	meat	bone
1	meat	cracked bone
0	gone	gone
One pass per layer, no exceptions — bone is not tougher in passes, it is tougher in handling (§4). Raising the layer count adds meat depth, not bone depth.

3 · Cutting
The bite matches the blade. Each cut samples the blade's swept path every 6px of travel and decrements every cell whose centre falls within the blade's radius — a round footprint the full 52px width of the disc. This is worth stating plainly because getting it wrong is the single most damaging bug in the piece: an earlier build stripped only a 26px strip under the blade's centre, and it read to players as "the saw randomly doesn't cut."
One decrement per cell per crossing. A set of touched cells is held for the duration of a crossing so a slow or re-entering blade cannot strip the same cell twice on one pass.
The blade bites from its edge, not its centre — cutting begins the moment the disc overlaps the limb.
Orphans fall away. After each crossing, any material no longer connected (4-way) to either the proximal or distal end of the court is removed with a spray of chips. Islands do not hang in the air.
Completion is connectivity, not geometry. The cut is through when a path of empty cells exists from the limb's left edge to its right edge, 8-way connected. A diagonal or stepped gap counts; a full straight row is not required.
Parting. On completion, everything no longer connected to the proximal end is flagged as the severed piece and slides away from the cut over ~2.2s while the scene fades to the report card. The gap shows table, not void.

4 · Feel
Element	Rule
Serve	The blade rests on the paddle it will jump from, ringed and labelled with a dashed aim line into the limb, and waits for Space. The player always knows where the next pass starts. Same on the opening serve and after every jump.
Paddles	Mirrored, one input (mouse Y, or W/S), 120px default. Return angle is classic Pong — contact offset from paddle centre, ±0.5 rad.
Bone handling	Read from the cells directly under the blade each frame, never from a whole-row scan (an order-dependent row scan silently disabled this mechanic for an entire build). Above 25% bone under the blade it slows 6–16% and chatters off its line; chatter scales down as bone coverage rises, so a limb that is bone edge to edge does not chatter several times worse than one with meat gutters.
Breakthrough	Once the gap has reached all but two columns, speed rises 15%.
The only botch	Missing the paddle. SAW JUMPED! burst, blood, chips, hard shake, −8 vitals, and the blade returns to rest on the paddle it got past. Vitals at zero is FLATLINE! and an automatic MALPRACTICE.
Sound	Filtered noise bursts: bandpass for soft tissue and paddle contact, lowpass for bone and for the jump. A sine drop for the flatline clunk. Mutable.

5 · Two patients
A toggle under the board switches patient and regenerates. Human: 236px wide, two bone shafts (58px and 34px) with meat gutters either side, warm skin. Seal flipper: 168px wide, 4–5 slim phalanges (7–10px) fanned across nearly its full width, and the slate hide from the sedation step — base #67757b with dark blubber rolls banding across the limb, mottled speckle and a few pale sheen flecks. The flipper is the narrower limb but nearly all bone, so it is faster to cross and harder to hold a line through; that trade is the point of the toggle.

6 · Rendering notes
Split the arm into two passes. Cell fills go to an offscreen canvas, redrawn only when material changes (a dirty flag set by every decrement and every orphan removal — miss it on the cutting path and the arm appears to update all at once at the end). The ink outline, the red seam inside every exposed edge and the shadow under every exposed upper face are redrawn live each frame on the shared 7Hz wobble clock, so the arm breathes like the paddles and the blade.
The page stays flat. No halftone screen, no sheet hatching, no centre line — the ink line work carries the drawing. Blood splats land anywhere and stain permanently; chips are short-lived particles in the colour of the layer they came from.

7 · Results and tuning
Report card: CLEAN / SLOPPY / MALPRACTICE stamp, time, strokes, jumps, stump quality, vitals lost, a flavour line, Retry. Stump quality compares material removed against one straight full-width channel (columns × layers × blade diameter ÷ cell height) allowed 1.5× for the overlap real play cannot avoid: clean ≤1.15, a little ragged ≤1.6, else ragged. Calibrate that reference against measured perfect play whenever the blade size, grid or layer count changes — if flawless play cannot earn "clean", the number is wrong, not the player.

Score = round(100 − jumps×9 − vitalsLost×0.5 − ragged − max(0, t−25)×0.7), clamped 0–100; CLEAN ≥78, SLOPPY ≥45. Knobs: limbType human | seal · layers 4 (4–8) · ballSpeed 820px/s (400–1100) · paddleHeight 120px (70–190) · chatter 0.7 (0–1.5). Target a good run at 12–18 seconds.

8 · Port notes
Model it as three parts: a depth grid with a swept-disc decrement operation, a flood fill used three ways (orphan prune, left-to-right completion test, severed-piece tagging), and one ball with Pong reflection. Nothing needs a physics engine. In an engine with a tilemap this is a tilemap; in one without, a byte array of columns × rows is enough, and the whole game state is that array plus a ball, a paddle position and a vitals float.

Two things to preserve. The cut footprint must equal the drawn blade — if they drift apart the game feels broken in a way players cannot articulate. And bone state must be sampled under the blade, per frame, not summarised over a row or the whole limb: both of the mechanic-killing bugs in this build came from a cheaper summary standing in for the actual contact.
