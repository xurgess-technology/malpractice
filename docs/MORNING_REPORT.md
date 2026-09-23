# Morning report — 2026-09-23: the pocket spaces

Written by the POCKET_SPACES_2 **phase 7** task on branch `pockets-phase7`, for someone who has
been away and has not played most of yesterday's work. Phases 1-6 are all on `main` (0.10.46);
phase 7 is the validation pass, and this is what it found.

(This replaces the arcade-surgery morning report of 09-21, which is in git history.)

---

## START HERE

Three things, in this order. Review windows open **minimized** and flash in the taskbar — click the
taskbar button to give one focus before you click inside it.

**1. The Onlooker, in the room it was built for.** It is the newest thing and nobody has played it.

    tools\review.bat main "ONLOOKER: check your sightlines" --setup=onlooker

Stand at one end of the Natatorium and look around. It appears far off, already in your view, and
stares. Turning your back buys you up to nine seconds before it relocates into wherever you are
looking now. Run **at** it to send it away; the saw and a shove do nothing.

The question I could not answer for you: **at 39 m in the Factory's fog it reads as a single pale
dot, not as a figure.** Visible — before phase 6's fix the frame was blank — but the two eyes merge
and there is no silhouette against the dark. The shot is
`tools\game_shots\p_factory_c_onlooker_stare.png`. In the Natatorium it is better lit. Whether you
want a tall shadow at range or just two eyes is a tuning call and it is yours.

**2. The Chapel, walked into rather than looked at.**

    tools\review.bat main "CHAPEL: does the nave read as you walk in?" --setup=chapel

Walk **in through an entrance and keep walking up the nave**. A pocket's own air — its fog and its
ambient — blends in over the first fourteen metres from a seam, so the first seconds of every one of
these rooms are drawn in the *hospital's* air and not their own. In the Chapel that means the vault
is a lit green haze at the back and goes dark as you walk up; in the Laundromat the room is dim at
the door and flat fluorescent by the middle. It is working as built and it is not new. But it is
the first thing you ever see of these rooms, and it has only ever been judged from screenshots
taken standing still in the middle of them. It cost me an hour this morning to work out that a
washed-out Chapel shot was this and not a regression.

**3. The five spaces as they stand.** No window needed — 130 shots taken this morning:
`tools\game_shots\p_factory_*`, `p_restaurant_*`, `p_natatorium_*`, `p_chapel_*`, `p_laundromat_*`.
Each space from six or seven places, an entrance from inside, **every seam from the hallway side**,
and both copies of every stub side by side (they differ by noise, 0.08-0.48%).

---

## What the pocket spaces are now, in a paragraph

Five of them: the **Factory** and the **Restaurant** you already had, plus a **Natatorium** (an
Olympic pool you wade across — the short way, and loud enough to be certain of being heard; the
only place in the game where crouching does not buy silence), a **Chapel** (a cathedral lit by its
own candles, and you can place one: inside its radius the Night Nurse counts as watched with nobody
there, for two minutes), and a **Laundromat** (every machine running, and the drone means a
Sonographer cannot hear you walk in there at all). One turns up on about a quarter of shifts, never
the same kind twice running, through two or three entrance stubs that look like ordinary wing
hallways. Each space has three items of its own that spawn nowhere else, and a trace of them bleeds
into the six to nine hospital rooms nearest an entrance, so the hospital hints at what is through
there. There is a fourth monster, the **Onlooker**, which only ever appears inside a pocket: it
feeds on being seen and ignored, and the counter is to walk at it.

---

## Judgment calls I made without you

- **I rebuilt how perfprobe measures instead of reporting its numbers.** It was measuring its first
  scenario before the engine had finished with the level — the same corridor reads **60 fps as a
  first row and 127 as a last row**, same camera, same map — and its "1% low" was the third-worst
  frame of about two seconds, which swung by a factor of four between runs minutes apart. The
  alternative was to publish the table as it came out and say "the bar is met", which is what the
  last three phases did in good faith. **The consequence for you:** every perf number in
  docs/POCKET_SPACES_2.md from phases 2, 3 and 4 should be read as not-a-measurement, including the
  ones saying a space beats the hospital beside it. That claim may well be true. The evidence for
  it was not.
- **I only swept medium (q1).** One preset measured properly rather than three measured badly. The
  q0/q2 picture is one command and about an hour if you want it.
- **I fixed the Night Nurse candle test rather than ticking the box.** A test existed and looked
  thorough. It was proving "she freezes" with a monster that had been told to stand still, and the
  "she moves again when it burns out" half had never been written. The rule itself turns out to be
  fine: **0.000 m while the flame burns, and she walks off at her full speed the moment it dies.**
  I only know that as of this morning.
- **I left two broken things alone deliberately.** Two other sections of `trinkettest` stand the
  player off the edge of the dev room's floor, exactly as the candle section did, and pass anyway;
  what they are quietly not testing deserves its own look, not a drive-by. And the Laundromat's
  frame cost I measured four times and did not chase.

---

## What needs your decision

1. **Syringes — already waiting for you from an earlier task.** Fixing a batch bug raised syringes
   from 3-6 a shift to **6-9**, and the old comment hints **1-2** may have been the intent all
   along. Three-way call about scarcity, and it is yours.
2. **The Onlooker at range** — START HERE item 1.
3. **Walking into a pocket through the hospital's air** — START HERE item 2.

---

## Where it stands, honestly

**Green, measured this morning on an idle machine:**

| | |
| --- | --- |
| `mapcheck`, 300 seeds, all five kinds | **464/464 pockets placed**, every entrance walks out through its own seam, nav 99.7-100% |
| `pockettest` | **PASS, 740 checks, twice** — includes the bot walking every entrance both ways carrying a body, the Sonographer masking, and the Onlooker in all five spaces |
| `monster_lab` | **179 checks, 0 failed** |
| `trinkettest` | **PASS, 0 failures**, now with a Night Nurse that actually walks |
| `pocketrate` (never run with five kinds before) | **23.9%** of 2000 shifts, in band, 0 rolls that found no room, no repeats |
| frame-rate **averages** | clear the 60 fps bar on every view of the Factory, Restaurant, Natatorium and Chapel |

**Not green:**

- **The Laundromat costs more than the other four, everywhere on its map** — including while you
  are looking at the hospital rather than at it. It is the only space whose process carries
  **15-20 ms of CPU a frame** against 9-13 for the others, in all four sweeps, and its interior
  sits at **69-97 fps average with 1% lows of 39-50** against a bar of 50. It is not the drawing:
  it draws half what the Chapel does. I did not find the cause. The lead is its ~40 lights with
  their flicker nodes, or its ~150 machine bodies.
- **The 1%-low half of the perf bar cannot be judged on this machine today.** In both careful runs
  some view gets pulled under 50 by a single 30-55 ms frame, and it lands on *untouched hospital*
  views as often as on new ones (one hospital corridor read 94 in one run and 34 in the next — it
  did not get slower). That is a **second independent sighting of the unexplained host stall
  already recorded as FAILING_TESTS 1j**, this time from the rendering side rather than headless.
  It is the most valuable loose thread on the board and it has nothing to do with pocket spaces.

**Known, old, and not mine:** the morgue trays out of reach on seeds 1, 38 and 112
(FAILING_TESTS 2). **FAILING_TESTS 1m is gone** — the corridor's 1% low of 30 was the instrument,
not the hospital.

---

## Skipped, and why

- **q0 / q2 perf sweeps** — one preset measured properly was worth more.
- **The Laundromat's CPU cost** — measured four times, cause not chased. That is a task.
- **No `nettest` run** — nothing in phase 7 touches replication.
- **The Onlooker's own chosen hop has still only ever been watched on one machine.** The nettest
  scenario drives hops by hand with the host's physics off, so it tests the wire and not the
  placement. Still the single most valuable gap in the pocket work, and still open.
- **The two `trinkettest` sections standing in the void** — noted in the file, not moved.
- **Nobody has played the six items phase 5 added**, and the restaurant pager's private buzz has
  never been seen on two screens at once.
