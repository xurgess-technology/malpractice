# Changelog

Everything that changes in **Malpractice**, newest first. One minor version per day of work, one
patch per thing we did that day. How to add to it: [RULES.md](RULES.md#changelog).

**2026-09-22 (0.10.x)**

- **0.10.10**: A door you can see is a door you can't walk through
    - Fixed: A hinged door standing wide open was completely walk-through -- the metre of solid door sticking out into the room had no collision at all, so monsters (and you) strolled straight through it. It's solid again, while still not catching you on its end when you cut the doorway corner.
- **0.10.9**: The surgery board stops chugging
    - Fixed: Blood on the page was being re-cut into triangles every single frame, so the messier you got the slower it ran. It's baked once now: the worst case went from about 4 ms a frame to effectively nothing, and it no longer gets worse the more you bleed on it.
    - Fixed: Everyone in the room was redrawing every surgery board at full speed, on every machine, for every table at once. Now only the person actually operating pays full price; onlookers redraw less the further off they are, and not at all when it's off screen. Whole painter is down from 5.6-6.8 ms to 1.9-2.4 ms.
- **0.10.8**: STICK! goes where you point it
    - Changed: The needle now lands exactly where your cursor is and sinks straight down from there, instead of sliding off along its own angle as it went in. Hold Space and it stops itself the moment it's in the vein -- no more letting go at the flash.
    - Removed: Blowing the vein, and the angle control. Aim is the whole skill now; you can still miss.
    - Fixed: The syringe tray no longer sits on top of the instructions in the corner.
- **0.10.7**: The order is stamped on the sheet
    - Changed: The big word a step opens on is drawn on the clipboard page again instead of floating on your screen, so it reads as part of the sheet you're about to play on -- and onlookers can see it on the board too. Still lands in the same spot at the same size whatever the step.
- **0.10.6**: Pull up a chair, the board's for everyone now
    - Changed: The surgery board is half again as big, sits higher off the patient and stands up steeper, so a teammate walking over can actually read what you're playing instead of squinting at a postcard on someone's chest. The operator's own view is unchanged.

- **0.10.5**: The corner HUD catches up
    - Changed: The Anesthetic Injection, DODGE! and WHACK!/WRAP! (wound and stump) all switch to the standardized corner HUD SUTURE! introduced -- rules as bullets, keybindings as boxed key caps, instead of the old one or two lines of mixed instructions. Each step's own top-right number (dose, vitals, blood lost, coverage) is unchanged.
- **0.10.4**: SUTURE!, closing the wound
    - Added: SUTURE! -- LinkedIn's Zip, themed as one continuous thread through the whole wound. Follow the numbered anchors in order, fill every open cell once, never cross your own stitch. Skin closes over each cell you thread and reopens if you back up.
    - Added: A deep laceration (4x4, stepping up to 5x5 once you've closed one clean) and an eye socket (6x6, fenced off around the eye) as the two boards.
    - Added: The corner HUD gets a new look for this step -- rules as bullets, keybindings as boxed key caps, vitals as the only number in the corner.
- **0.10.3**: Dropped items hover
    - Changed: An item on the floor now hovers with a soft glow instead of settling flat wherever it landed, and the box you can grab it from is a lot more forgiving -- basically a full sphere around it.
    - Changed: Drop one where another's already floating and it hops to the nearest open spot instead of the two overlapping.
- **0.10.2**: WHACK! and WRAP!, rebuilt: the bleeders get packed, then the wound gets a roll of gauze
    - Changed: WHACK! is one clean hold-to-close commit on a bleeder that's actively spurting, not a click; the blood loss meter only rises while a bleeder is open, and it's drawn as local drips and splats instead of a screen-filling tint.
    - Changed: WRAP! is Snake played straight -- the tail is the gauze in hand, delivering it onto a wound cell spends a segment, and cells that bled through in WHACK! need a second layer.
    - Changed: The stump dressing plays the same WRAP!, with the tourniquet's quality standing in for pack quality.
    - Removed: The old WHACK! and WRAP!, off the clipboard shell.
- **0.10.1**: The stamp card holds still
    - Changed: The big word every step opens on (SAW!, DRAW!, DODGE!, ...) now shows up in the same spot in front of the patient no matter which step or site it's for, instead of riding the clipboard panel to wherever that step is anchored on the body. A bit bigger, too.
- **0.10.0**: Dissection is gone
    - Removed: The monster-dissection cases -- forceps brain harvest and the skull saw -- and everything that only existed for them: the dissection minigame files, the dev-panel monster-strap flow for it, its headless test and nettest scenario, and the Sonographer's old strapped-patient identity. The Hive's Eyeball Extraction is now the only monster case a strapped patient can have.
    - Note: The shared gunshot-forceps and limb-amputation-saw minigames are untouched. The Brains hive-AI/loot system (unrelated, same word) is untouched, though its brain-item supply chain ran through the removed dissection code and has no live source left -- matches the removal already planned in docs/GRAFTING.md.

**2026-09-21 (0.9.x)**

- **0.9.2**: DODGE!, rebuilt: fly the bullet out with the lights on
    - Changed: DODGE! is Flappy Bird down the bullet's own channel. Space flaps and that's it; the whole tract is visible, and the dark, the flashlight and the brake are gone.
    - Changed: The walls only pinch when the patient squirms, and they only squirm if you under-dosed them. SQUIRM!
    - Changed: Clip a wall and it tears: the game stops on a TORN! card for two seconds, you get dragged back, and the press that restarts it flaps.
    - Changed: Every tear still comes back as its own bleeder when you pack the wound.

- **0.9.1**: The Anesthetic Injection, and every step is a page on a clipboard now 📋💉
    - Changed: Sedation is the Anesthetic Injection, and DOSE! is gone. Draw the plunger into a green band set by the patient's weight, flick the bubbles out, then slap up a vein, stick it at the right angle, stop at the red flash and push. Slowly.
    - Changed: The needle goes in exactly where you point, and you can see the part that's under the skin.
    - Added: The clipboard. The panel is a sheet clipped to a board, drawn in boiling hand-inked lines, with the step's name on the clip.
    - Added: Stamp cards. Each stage opens on a big word (DRAW! FLICK! STICK! PUSH!) that waits for you, and the press that clears it does the first thing.
    - Added: Mistakes shout (MISS! BLOWN! AIR! TOO FAST!) and splatter blood across the page, and the blood stays. Teammates watching see the same mess.
    - Added: A tourniquet in your hands can pin the vein up for you, and it uses the tourniquet up.
    - Removed: The old sedation games, both of them. One version per game.

- **0.9.0**: EVERY SURGERY STEP IS AN ARCADE GAME NOW 🕹️🫀
    - Added: DOSE! -- an old golf power meter, twice. Stop the needle on the vein, then fill the syringe by eye. The dose is still by weight and still never a number.
    - Added: DODGE! -- the forceps grip the bullet on their own and you fly it back out of the wound tract, in the dark, while the walls pinch on every heartbeat. A teammate's flashlight doubles how far you can see.
    - Added: WHACK! then WRAP! -- whack-a-mole over the tract you just tore, then Snake with a roll of bandage. Every wall you clipped on the way out comes back as its own bleeder.
    - Added: SQUEEZE! -- the fishing bar. Slide the strap up a limb while the rot creeps toward you, then hold a pressure bar over a wandering pulse until the windlass locks.
    - Added: SAW! -- Pong. The blade is the ball and it goes straight through the limb. Bone makes it heavy and makes it chatter.
    - Added: WRAP! the stump -- Snake round a ring, two layers on everything, and a finite roll.
    - Added: STEER! -- a ring race round an eye that watches the blade and lunges at it.
    - Added: PRY! -- lockpicking. Feel for the quiet spot on each tether and lever until it pops.
    - Added: CUT THE RIGHT ONE! -- bomb defusal. The rule shows for a second and a half, the strands come out knotted, and combing them out is the thing that hurts the patient.
    - Added: GRAB! -- a claw machine, with an eyeball swinging on its nerve.
    - Added: STITCH! the graft in -- the suture ring round a socket, dots hidden under the blood you spilled driving round it.
    - Added: Your mistakes follow you. A bad tourniquet blinds you in the saw, a torn tract becomes more bleeders, a bad dose leaves them stirring all case, and the wrong dose in the seal leaves it half awake.
    - Added: Step away mid-game and it freezes exactly where it was; whoever picks it up gets a READY countdown instead of a free failure.
    - Added: Every step opens with a one-word order slammed across the panel. SAW!
    - Note: All of them are on. The dev panel's Arcade surgery checkboxes turn any of them back off, and every old version is still there underneath.

**2026-09-20 (0.8.x)**

- **0.8.2**: THE MACHINE RUNS ARCADE SOFTWARE 🕹️🦴
    - Added: Surgery steps can be short arcade minigames on the panel: a one-word command card to start, and the game freezes if you walk off so whoever picks it up gets a READY countdown instead of a free failure.
    - Added: SAW! -- alternating A and D to a cadence, through a cross-section of the actual limb. A pendulum keeps the beat for whatever the blade is in, and it changes the moment the blade meets bone.
    - Added: Rush the saw and it jumps, tears and costs you. Nearly through, the card says EASY -- come off the last strokes too fast and you saw into the table.
    - Added: The artery in the muscle answers to your tourniquet. A good one dribbles. A bad one sprays across the panel, buries the pendulum, and you finish the cut by ear.
    - Note: Off by default. The dev panel's Arcade surgery checkboxes turn each one on; every step still plays its old version until you do.
- **0.8.1**: The panel stands up and gets out of the way
    - Changed: The panel is bigger and stands up off the patient instead of lying nearly flat over him, so onlookers can actually read it from where they are standing. It looks the same size to whoever is operating.
    - Added: When something goes wrong -- a torn stitch, a gush, a patient jerking -- the panel goes see-through for half a second so you watch him take it, then comes back.
- **0.8.0**: A PANEL TO OPERATE ON 🩹📋
    - Added: Surgery can be played on a panel: a flat glowing diagram that pops in over the wound when you start operating, faces you, and shows the step as an openly 2D board. The real patient stays visible all round it, and when you step back the panel goes with you.
    - Added: Onlookers see the panel as a real object hanging over the table, from wherever they are standing, and its glow falls on the patient and your hands.
    - Added: Deep laceration, a one-step test procedure for it: a gash that gapes wider in some stretches than others, five stitches, press-drag-release. Good stitches shut a section, sloppy ones hold but keep seeping, and burying the needle in the gash rips the thread through.
    - Added: The cut is on the patient, not on the diagram. It is open in the gown before anyone walks up, and afterwards it is stitched -- neat for good work, crooked for bad -- and he walks out of the hospital wearing it.
    - Changed: Suture kits are sterile peel-packs now, with the curved needle, the coil of thread and the needle driver visible inside. New icon to match.
    - Note: Deep laceration never turns up in a shift. It is in the dev panel's patient list and the minigame lab, to try the panel out.

**2026-09-19 (0.7.x)**

- **0.7.2**: THE SONOGRAPHER HUNTS 🩺👂
    - Added: Quiet noises make the Sonographer suspicious and his neck stretches as it fills, so you can see how close he is to echoing. A loud noise sends him straight to the spot.
    - Added: A full neck charges, then fires an echo: a fan of ultrasound out of the wand. Walls and closed doors block it, and later shifts and deeper wings sweep it wider.
    - Added: Everyone the echo catches is imaged (scan grain over the screen) and deafened by a short squeal with the game muffled under it. There's a Squeal NORMAL/SOFT setting.
    - Added: He rushes the nearest player he imaged and wails on them, stopping to listen now and then so you can slip away. He follows sound, so going quiet for a few seconds loses him, and a shove gets him off you.
    - Added: New sounds for his charge, echo, squeal, rush and wail.
- **0.7.1**: ONE WAY TO HANDLE AN EYEBALL 👁️🫙
    - Changed: An eyeball is picked up and put down the same way everywhere: hold left click on it, drag it where it goes, let go. It can't be dropped, fumbled or lost, and letting go anywhere else puts it back for free.
    - Added: The Hive's extraction ends with carrying its eye to a specimen vat, so the eye never touches the floor.
    - Changed: The new eye for a graft waits in a vat instead of on a tray, and comes out with the forceps.
    - Added: Every surgery step says what each button does, under its hint.
    - Changed: A big rectangular steel table in the OR, with room beside the patient. The specimen vat stands on it; the vat stand is gone.
    - Fixed: The grafted eye was going in backwards, which read as a red blob. It's an orange Hive eye now, the right way round and the right size.
    - Fixed: The patient no longer appears to shift on the table between surgery steps, and the operating view doesn't bleach a pale face.
- **0.7.0**: Quiet, please 🔇
    - Changed: The game starts at 10% volume.

**2026-09-18 (0.6.x)**

- **0.6.16**: The Discharged is gone, the Sonographer is in 🩺
    - Removed: The Discharged, its IV pole and its rattle. Its kind is the Sonographer everywhere now: shifts, brains, the database, dissection and the dev tools. Old databases keep its page.
    - Added: The Sonographer walks the halls. He clicks as he goes and squelches through the gel, and both stop when he stops to listen; his neck grows while he listens and searches.
    - Changed: He hunts the way the Discharged did for now (listen, rush, search). The echo and the rest of his hunting are next.
- **0.6.15**: The Sonographer, finished
    - Changed: He looks almost normal until he gets suspicious, and then his neck grows, and grows, with the glowing windpipe stretching up it.
    - Changed: His right hand is gone: the arm ends at the wrist and an ultrasound wand is fitted there. No cable.
    - Changed: Ears that look like part of his head, a cleaner shoulder and collar line, no head tilt when he charges, and gel that really drips off him.
- **0.6.14**: Slim pickings, full shelves
    - Changed: Loot is scarce: 15 to 20 finds a shift instead of 70, and a shift pays about $1,000 instead of $11,000. Most rooms hold nothing, and a harvested brain is a real chunk of the pay.
    - Changed: Pill bottles and X-ray film are cheap filler now; the ultrasound, heart monitor and gold watch are where the money is.
    - Changed: Anything that fits can turn up in a drawer, bag or pegboard, desk phones and laptops included.
    - Changed: About half again as many surgery supplies: three of every tool the case needs, more anesthetic and gauze, and more of the ones it doesn't.
- **0.6.13**: GRAFTING!!! YOU CAN NOW HAVE A HIVE EYE!!!!!!
    - Added: Every OR table has a vat stand. Strap a surgeon down, put a vat with a Hive's eyeball on the stand, and a teammate swaps it in for one of their eyes: scalpel, eye spoon, eye spoon, stitches. The patient is awake for all of it.
    - Added: A grafted surgeon has one normal eye and one glowing orange Hive eye, on their own body, in the mirrors and on other players' screens, and gets Hive Eyes. Swap back and it's gone.
    - Changed: Hive Eyes only comes from the graft now. The Hive brain no longer teaches it at the blender.
- **0.6.12**: Less to loot
    - Removed: Thirteen kinds of loot (stethoscope, wedding ring, coffee maker and friends).
    - Added: EpiPen and a new pulse oximeter. Trinkets, the loot that also does something, are rarer: three to five a shift.
    - Changed: Radiology and the other rooms that lost loot get some back, and a shift pays about the same.
- **0.6.11**: Icons for everything 🖼️
    - Added: The item bar is icons now: four slots, a name that flashes when you switch, bulky things take two, and a spoiling part drains around its slot.
    - Added: Icons in the ability bar, the database and the OR screen, and picked-up items fly into their slot.
- **0.6.10**: Eyeball Extraction 👁️
    - Added: Take a strapped Hive's eye out with a scalpel and an eye spoon: trace the cut and watch it open on the skin, circle the socket with the spoon, lift the eye on its nerve and slice it.
    - Added: Specimen vats on the lab wall. Put an eye in one to keep it from spoiling, carry it, set it on a lab bench. Eyes spoil outside a vat and sell at the furnace.
    - Added: The scalpel and eye spoon in the OR storage, and jars of heads on the lab wall.
- **0.6.9**: Lie down, doc
    - Added: Hold E at an OR table to strap yourself down, face up and awake. Let go and hold E again to get up.
    - Changed: A strapped-down body lies along the table for everyone, with no torch or other light on it.
- **0.6.8**: A new way of working 🧑‍⚕️🧑‍⚕️🧑‍⚕️
    - Added: One orchestrator agent hands work to subagents in four reusable work slots; see [RULES.md](RULES.md#workflow).
    - Added: Review windows: a game window from a slot, titled with what to go look at. It waits in the taskbar instead of popping up in your face.
    - Changed: Play it first, test it hard later; big test sweeps get batched.
- **0.6.7**: Spring cleaning 🧹
    - Removed: The first Night Nurse, unused models and the old web prototype (moved to `deprecated/`).
    - Removed: Sounds nothing played, and about 320 MB of old screenshots, logs and caches.
- **0.6.6**: Paperwork
    - Added: This changelog, and [RULES.md](RULES.md) for how we work.
    - Added: The art style for characters and models, written down in DESIGN.md.
- **0.6.5**: The Hive gets a glow-up 🍄
    - Changed: A new Hive: charcoal skin, and a shelf fungus growing out of its broken-open skull.
    - Added: Its own shamble and lunge, and eyes that flood orange once it's seen you.
    - Changed: There's no brain to take out of it for now; that part is being rethought.
- **0.6.4**: THE NIGHT NURSE HAS YOU BY THE THROAT 🫲🫲🫲
    - Changed: She grabs you and drops you downed instead of taking hearts.
    - Changed: A new look in the game's art style.
- **0.6.3**: Cameras
    - Added: F5 cycles first person, over the shoulder, and a view facing you.
    - Fixed: Your flashlight no longer shines on the back of your own head.
- **0.6.2**: ROCKET BOOTS 🚀🚀🚀 THE SHOP SELLS A REAL THING 🚀🚀🚀
    - Added: Rocket boots at the pharmacy: fly on a fuel bar, faceplant into walls.
- **0.6.1**: The hub fills in
    - Added: A personnel room with working mirrors, and the OR's lab wall, storage and janitor's closet.
    - Changed: Surgical tools work straight from your hands, and the dive flies flat out.
- **0.6.0**: Code Blue is dead, long live Malpractice
    - Changed: The project is renamed everywhere.

**2026-09-17 (0.5.x)**

- **0.5.4**: Polish
    - Changed: The Walk-In is now the Hive.
    - Changed: Faxes move faster and get rubber stamps; a shift assignment fax starts every session.
    - Changed: The carry camera sits over your right shoulder; throws have a wind-up.
    - Changed: The saw follows a skin-marker line instead of a glowing guide.
    - Fixed: The paramedics' gurney no longer shoves you out of an operation.
- **0.5.3**: The outside world
    - Added: The hospital's exterior, and you arrive by walking out of the fog.
    - Changed: Wander too deep into the fog and you get lost instead of steered back.
- **0.5.2**: A NEW DOCTOR IN THE HOUSE 🩺 (THE STYLIZED SURGEON)
    - Added: The players' new body, built from Python in Blender.
- **0.5.1**: WE ARE NOW MALPRACTICE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    - Changed: The game is **Malpractice**, and the hospital is **St. Doe's General**. RIP Code Blue.
- **0.5.0**: The wall terminal
    - Added: A shared projector screen in the break room: sign in with your scan laser, everyone sees everyone's.
    - Changed: The database is a slide projector with a lock screen.

**2026-09-16 (0.4.x)**

- **0.4.5**: Polish
    - Added: Dead patients go to the furnace; the saved walk out.
    - Changed: Surgery can use supplies from your hands, and the ability hotbar is round.
    - Changed: The default camera went over the shoulder and back again by the afternoon.
    - Fixed: Spoiled brains no longer sell at full price. Nice try.
- **0.4.4**: The wall terminal, part one
    - Added: A projector screen, a scan laser, and a database per player.
- **0.4.3**: THE HUB REBUILD 🏥🏥🏥 (FROM ZACH'S ACTUAL FLOORPLAN)
    - Added: Three OR tables, the lobby, a fax pharmacy, a crematorium furnace and a break room.
- **0.4.2**: Faxes everywhere
    - Added: The title menu, the settings screen and first-time tips are all faxes now.
- **0.4.1**: Loading that never freezes
    - Added: A heart monitor loading screen, with levels built in the background.
    - Added: Windows export builds.
- **0.4.0**: Sprint-dive and prone
    - Added: Crouch while sprinting to dive; the crouch key cycles stand, crouch and prone.

**2026-09-15 (0.3.x)**

- **0.3.4**: Polish
    - Changed: Things you can use highlight when you aim at them.
    - Changed: The first call rings as soon as you clock in, and the OR doors open with E.
    - Added: Exit to Main Menu and Exit to Desktop on the pause screen.
- **0.3.3**: The database terminal
    - Added: A terminal that replaces the medical guide.
    - Changed: Hive Eyes and Echo look the part.
- **0.3.2**: GOODBYE GOLD BARS 💸 HELLO PHARMACY
    - Added: The pharmacy (placebo pills, emotionally supportive) and the crematorium furnace for selling loot.
    - Added: Charged throws.
    - Removed: Gold bars and the sell bin.
- **0.3.1**: The fog lot
    - Added: A ring of fog, and an ambulance that drives in for every delivery.
- **0.3.0**: Crouch, jump, abilities, scanner
    - Added: Crouch and jump, ability slots on Alt+1-4, and a scanner for learning about monsters.

**2026-09-14 (0.2.x)**

- **0.2.5**: New faces
    - Added: Blender-built players, paramedics and Bob, the seal patient, and the Night Nurse's model.
- **0.2.4**: Hands
    - Added: First-person arms, items held properly, wind-ups and the carry camera.
- **0.2.3**: Pocket spaces
    - Added: The Factory and the Restaurant, stitched into the hospital through seams.
- **0.2.2**: Doors
    - Added: Room doors and locked wing gates, with the wings rebuilt every shift.
- **0.2.1**: Dissection
    - Added: Monster patients, a skull saw and brain forceps.
- **0.2.0**: Monsters
    - Added: The Walk-In (now the Hive), and a redesigned Discharged.
    - Changed: Monster meshes baked down from ~90 draw calls to ~6 each.

**2026-09-13 (0.1.x)**

- **0.1.7**: Brains and combat
    - Added: Brains that spoil, the blender, and the Echo and Hive Eyes abilities.
    - Added: Saw swings, anesthetic jabs, and dragging sedated monsters to a table.
- **0.1.6**: The shift loop
    - Added: Several patients at once, the phone, paramedics, clocking out and game over.
    - Added: The OR wall monitor.
- **0.1.5**: Downed players
    - Added: 0 HP downs you: crawl, bleed out, get carried to a table and stitched up.
- **0.1.4**: A generated hospital
    - Added: Wings of hallways and rooms, furnished and lit.
- **0.1.3**: Inventory and money
    - Added: Four hand slots, bulky and sellable loot, and money.
- **0.1.2**: Multiplayer
    - Added: Host over Steam or IP and join mid-shift.
    - Changed: Netcode rewritten to send each field on its own, so bad connections catch up.
- **0.1.1**: Surgery that feels right
    - Changed: Every surgery minigame gives feedback in the world instead of gauges.
- **0.1.0**: THE HOSPITAL IS OPEN 🚑🚑🚑 (AGAINST MEDICAL ADVICE)
    - Added: Code Blue, a co-op hospital horror game in Godot, and the web prototype it grew from.
    - Added: Settings, and a secret dev room.
