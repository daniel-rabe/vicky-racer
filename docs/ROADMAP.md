# Vicky Racer — Roadmap after v1

v1 (Phases 1–8, [`DESIGN.md`](DESIGN.md)) is one track, six drift setups, three opponents and a
garage. This document plans what comes next. It keeps the rules that got v1 here:

- **Art before code.** Every milestone that needs new art opens with mockups and candidate sheets,
  and nothing is built on top of them until they are approved.
- **One frozen recipe.** New images go through [`tools/comfy/pipeline.json`](../tools/comfy/pipeline.json),
  new sounds through [`tools/comfy/sfx_manifest.json`](../tools/comfy/sfx_manifest.json): pinned
  seeds, four candidates, one pick. Quality over speed.
- **Data, not code.** A new car is a `.tres`, a new track is a layout script plus a `TrackConfig`, a
  new cup is a `CupConfig`. Nothing should need a code change to add content.
- **Forgiving by construction.** Every new feature is checked against the pillars: a young child
  can play it, cannot get stuck in it, and is never told they lost.
- **Headless tests at every gate**, extended rather than replaced, plus a run of
  [`tools/dev/balance_report.py`](../tools/dev/balance_report.py) whenever handling or AI changes.

Milestones are in the recommended order. Each one is playable on its own when it lands.

| # | Milestone | Why now | Size |
| --- | --- | --- | --- |
| 9 | Front end, pause and assists | Escape in a race throws the race away today; a child needs a title screen, a pause menu and an auto-accelerate option before anything else | S |
| 10 | More cars | The garage has six things to buy; a growing child runs out in about 20 races | M |
| 11 | Track pipeline and three new tracks | Tournaments and variety both need tracks; the pipeline has to scale from one hand-made track to many | L |
| 12 | Tournament mode | A cup of races with points and a trophy, the classic kart-racer goal | M |
| 13 | Music | The races are silent apart from engines | S |
| 14 | Trophy shelf and stickers | Rewards a child who cannot read yet can see and collect | S |
| 15 | Two players, split screen | Racing with a parent or sibling on the same sofa | L |
| 16 | Time trial and ghosts | Something to come back to once the cups are won | M |
| 17 | Release build | A real Windows build that starts from a desktop icon | S |
| 18 | Three more tracks in new themes | More places to race once the two cups are won | M |
| 19 | Free Drive: the town | Somewhere to just drive, with nobody to beat | L |
| 20 | Boats: racing on water | A second racing game with its own boats, courses and cup | L |
| 21 | The island: harbour and ocean in Free Drive | Take the boat out from the town, round the island | M |

---

## Phase 9 — Front end, pause and assists ✅ done

Built as planned, with three changes found on the way, all in [`DESIGN.md`](DESIGN.md) §3.1,
§8.3 and §10:

- **Settings got their own file** (`user://vicky_settings.cfg`) instead of a save-schema bump:
  machine settings and the child's progress should not be able to break each other.
- **One SOUND slider for now**; the `Music` bus exists and gets its slider with Phase 13.
- **AUTO GO cruises at 65 %** of top speed rather than flooring it: at full throttle, AUTO GO plus
  STEER HELP won races with no input at all. Now that combination finishes 3rd.
- Difficulty is **EASY / NORMAL / FAST** (not "hard": the word is for a child).
- Found and fixed on the way: car-to-car contact counted as a wall hit, scrubbing speed and shaking
  the camera every time two cars touched.

Tests: `front_end_test` (title, settings file, settings apply/save, pause, confirm, auto
accelerate, difficulty) and `assist_test` (hands-off laps).

---

## Phase 10 — More cars ✅ done

Built as planned — six new cars, off-road ability, per-car skid/smoke colour, engine pitch and
horn, the Police Car's siren lights, the paint shop, garage pages and opponents in roster cars.
Details in [`DESIGN.md`](DESIGN.md) §4.2, §8.1, §8.3 and §9.3. Changes on the way:

- **Opponents pace from the base car**, not their own: in Banana and Dragon they ran away from a
  child in the Ice-Cream Van. Their car now sets handling and look, not difficulty.
- **Formula and Dragon toned down** after the balance report (clean wins by 6.2 s and 4.2 s).
- Two cars needed a second prompt (Monster Truck too like Grippy; Bubble Car in perspective).
- The palette is original + blue, yellow, green, purple, pink; opponents wear blue / yellow / green.

---

## Phase 11 — Track pipeline and three new tracks ✅ done

Built as planned: tracks as JSON specs, themes, Sunny Beach / Snowy Peak / Toy Town, ice (ponds and
on the road), boost pads, track select with unlocking by finishing. Details in
[`DESIGN.md`](DESIGN.md) §7. Changes on the way:

- **Bridges after all** (asked for after the first build, with longer tracks): figure-of-eight
  Meadow Loop, a mountain bridge on Snowy Peak, a flyover in Toy Town. The ambiguity at the
  crossing is solved by searching each car's position locally (DESIGN.md §7.7). All tracks were
  lengthened to ~22–31 s laps; save schema 3 drops best laps from the short tracks.
- New surfaces **beach** (softer than a sand trap, for the easy track) and **snow** besides ice.
- Snowman and toy house re-prompted to be truly top-down (described as seen from above).
- Toy Town shares the meadow's ground tiles; only kerbs and props differ.

---

## Phase 12 — Tournament mode ✅ done

Built as planned (DESIGN.md §12): Sunshine and Snowflake Cups of three races, points 10/7/5/3,
standings between races, a podium with confetti and a gold/silver/bronze trophy or ribbon, cup
bonus coins, progress saved after every race with CONTINUE CUP on the title. Changes:

- **The next cup opens when the previous one is won** (1st overall) — the user's decision,
  stricter than the proposal (finishing).
- **No reverse tracks**: four tracks make two cups of three without them.
- No save-schema bump: `[cup]` and `[trophies]` are optional sections.

---

## Phase 13 — Music ✅ done

Built as planned (DESIGN.md §13): a menu theme, four race themes (one per track theme), a
standings sting and podium music, cut into whole-bar loops with a seam check; `MusicManager`
cross-fades on screen changes, ducks under the countdown and the pause menu, fades out at the
finish and speeds up 6 % on the last lap; MUSIC volume in the settings. Changes:

- **No ACE-Step bake-off**: it is not installed (only Stable Audio is), and a multi-GB download
  was not worth it before hearing Stable Audio's music. The probe chose cfg 6 over 7 (clipping).
- **Last lap is a tempo/pitch nudge**, not a second stem.
- **The podium music replaces the finish fanfare there**: it opens with a fanfare of its own.
- **Picked from scores, not yet by ear**: the listening page (`generate_music.py listen`) is for
  the user to confirm or swap them.

---

## Phase 14 — Trophy shelf and stickers ✅ done

Built as planned (DESIGN.md §14): a shelf screen from a trophy button on the title, seven
stickers, a popup over any screen, saved in an optional `[stickers]` section. Changes:

- **Pile of Coins needs 200**, not 100: a win alone pays 100, so it would always come with
  First Win. The cup bonus counts toward it.
- **The shelf is a title-screen room**, not a garage tab: the garage has no room left.
- **The sticker edge is drawn in post**, not generated, so all seven share one die-cut look.

### Plan as written

Rewards that need no reading.

1. **Trophy shelf** — a garage tab (or title-screen room) showing every cup trophy and ribbon won.
2. **Stickers** — small achievements shown as stickers in a book: first drift, a 3-second drift,
   first win, every car owned, a lap with no wall hits, finishing on every track, 100 coins in one
   race. Each emits `PRO_sticker_earned` and shows a big sticker popping onto the screen.
3. **Saved in the profile**; a sticker can never be lost.

**Art gate:** one sticker illustration per achievement and the shelf background, through candidate
sheets.

**Done when:** each sticker has a headless test that triggers it, and none can be earned twice.

---

## Phase 15 — Two players, split screen ✅ done

Built as planned (DESIGN.md §15): a join screen where each player claims a device by pressing
it, per-player actions, two SubViewports sharing one world, a HUD per half and one minimap,
rubber-banding to the slower player, both players paid into the family garage. Changes:

- **Opponents ON/OFF is on the join screen** (O / Y), not a setting.
- **The race waits at most 30 s** for the second player after the first finishes; a finished
  player's car is driven on by the AI so it never blocks the other.
- **No cups for two players** — they are one child's progress.
- **Each HUD is mirrored** about the middle so the shared minimap has room at the bottom.
- **No particle cut per view**: the split race runs at 100 fps (vsync-limited) here; the
  release-machine check moves to Phase 17.

### Plan as written

The most social feature: a child racing a parent on the same screen.

1. **Second player input** — device-aware actions: player 1 is keyboard or gamepad 1, player 2 is
   gamepad 2 (or the arrow keys while player 1 uses WASD). A "press A to join" screen.
2. **Split screen** — two `SubViewport`s side by side (left/right suits the 16:9 screen and
   top-down tracks), each with its own chase camera; one shared `World2D`. The HUD becomes per
   viewport; the minimap is shared in the middle.
3. **Grid** — two players plus two AI (or no AI as an option). Rubber-banding bands to the *slower*
   player, so the child is kept in the race.
4. **Results** — both players' coins go into the same garage (one family profile), so co-op racing
   still progresses the save.
5. **Performance** — two viewports double the draw cost; profile on the release machine, and drop
   particle amounts per viewport if needed.

**Done when:** a two-player race runs at 60 fps with both cars on gamepads; a headless test spawns
two player cars on autopilot and checks per-player positions and results.

---

## Phase 16 — Time trial and ghosts ✅ done

Built as planned (DESIGN.md §16): a RACE / TIME TRIAL switch on PICK A RACE, a three-lap run
alone with records per track and per car, the player's record ghost and a gold developer ghost
per track. The ghost replays the recorded lap 0.0000 px from the car's own trace. Changes:

- **A time trial is three laps** with results, not an endless session: a child needs an end.
  It pays no coins.
- **Both ghosts at once**: the gold developer ghost is the target, the white one is you.
- **The ghost records the draw layer too** (one byte a tick) so it stays visible on bridges.
- **Ghost files are plain data** (`store_var`, no objects), the developer ghosts are `.res`.
- Found on the way: a save that already qualified for a sticker (e.g. every track finished
  before Phase 14) crashed the sticker popup at start-up. Fixed.

### Plan as written

1. **Time trial** — the player alone, best lap per track and car, from the track select screen.
2. **Ghosts** — record the player's position and rotation every physics tick of the best lap
   (compact: ~30 s × 60 Hz × 3 floats), replay it as a translucent car. Saved per track.
3. **Developer ghosts** — a ghost recorded by the autopilot at full pace shipped with each track,
   as a target to beat.

**Done when:** a ghost replays the recorded lap to within a pixel (headless test), and survives a
save/load.

---

## Phase 17 — Release build ✅ done

Built as planned (DESIGN.md §17): a 125 MB single-file `VickyRacer.exe` (pack embedded), icon,
splash, version 1.0.0, window title and remembered window, a performance pass and the playtest
checklist ([`PLAYTEST.md`](PLAYTEST.md)). It runs from a clean folder with no editor or tools on
this machine; the other-machine check is the first item of the playtest. Changes:

- **Icon and splash are composed** from the approved car and the title's font, not generated.
- **The internal project name stays VickyRacer** (it is the save folder); the window and the
  .exe say *Vicky Racer*.
- **Found by exporting:** opponent colours stored as a PackedColorArray came out empty in the
  exported game; now an Array[Color], and all 45 config resources are checked identical in the
  project and the pack.
- **No performance cuts needed**: the busiest case (two views, four cars on ice) is 0.6 ms a
  frame here. `--fps` in the .exe checks a new machine.

### Plan as written

1. **Windows export preset** — icon, product name, version, and an export filter keeping `tools/`,
   `docs/` and `tests/` out of the pack (`docs/mockups/` is imported today, so it would otherwise
   ship).
2. **Boot polish** — splash with the logo, window title, remembered window/fullscreen state.
3. **Performance pass** — profile the busiest moment (4 cars drifting on ice, full particles, two
   viewports) on the target machine.
4. **Playtest with Vicky** — a short checklist of what to watch for (where they get stuck, what
   they skip, what they laugh at), and a follow-up list from what is seen. The audience is the
   final test of every pillar.

**Done when:** the exported `.exe` runs from a clean folder on another machine, with no ComfyUI
and no editor installed.

---

## Phase 18 — Three more tracks in new themes ✅ done

Three tracks, each in a theme of its own, and a third cup (DESIGN.md §7, §7.3, §7.5, §12, §13):

| Track | Theme | Ground / patches | What it adds |
| --- | --- | --- | --- |
| **Jungle Run** | jungle | jungle / mud | the twistiest track: S-bends, a hairpin and a loop over a log bridge |
| **Candy Lane** | candy | pink icing / chocolate | a heart-shaped circuit with a boost pad on each long diagonal |
| **Moon Base** | moon | moon dust (low grip) / craters | a loop-the-loop over a bridge, two boost pads |

- **The Starlight Cup** (Jungle Run, Candy Lane, Moon Base) opens when the Snowflake Cup is won.
- **Six new surfaces**, all data in `Track.SURFACES`: jungle and mud, candy and chocolate, moon dust
  and craters. Moon dust grips least of any ground (0.45), so Moon Base slides wide off the road.
- **PICK A RACE scrolls**: seven cards and three cups no longer fit across the screen, so both rows
  scroll sideways with the focus and the last track raced is scrolled into view.
- **Made without ComfyUI.** The props, wall props and the star cup icon are drawn by
  `tools/layouts/prop_art.py` in the clay look, and the three race pieces are synthesised by
  `tools/comfy/synth_music.py`. Both can be swapped for generated versions file for file; the
  music prompts are already in the manifest, unseeded.
- Developer ghosts recorded for the three tracks; EXPLORER now needs all seven tracks finished
  (a sticker already earned is kept).
- Balance: a struggling child (0.7 pace) reaches the podium on every new track in the Starter
  car; in the Ice-Cream Van they finish 3rd on Jungle Run and Moon Base and 4th, 2.2 s back, on
  Candy Lane.

---

## Phase 19 — Free Drive: the town ✅ done

An open-world mode beside the races (DESIGN.md §19): **TOWN** on the title screen.

- A town of 5 × 4 blocks on a street grid with zebra crossings, a two-block park with a fountain,
  a pond and a playground, another pond and playground, and a ring of trees round the edge.
- **Fourteen buildings**, all facing the viewer like a picture-book map: candy shop, ice cream
  parlour, toy shop, bakery, pet shop, pizza place, flower shop, fire station, police station,
  school, car wash and three family houses — generated as Kontext edits of flat block sketches,
  because FLUX alone only draws buildings isometric.
- **A living town:** 24 vehicles (every car in the garage plus buses, vans, a fire engine and a
  garbage truck) keep to the right-hand lane, take turns at junctions, stop for ducks, toot at a
  child parked in their way and then drive round them; dogs and cats walk the pavements, duck
  families cross at the zebras, balloons, birds and cloud shadows pass overhead, birdsong.
- **Things to do:** coins in the streets (banked at once), shop signs when pulling up at a
  door, a bonus for visiting every kind of place, bubbles at the car wash, a pond to splash
  through.
- New generated art: 14 buildings, 4 vehicles, 4 animals, park props, a balloon; new sounds:
  quack, woof, meow, town ambience. `tests/town_test.gd`.
- **The car wash** (asked for after the first build): driving onto the wet blue pad in front of
  it washes the car — foam, soap bubbles, a spray-and-brushes sound — and the car comes out
  gleaming and **sparkles** with twinkling stars for 25 seconds.

## Phase 20 — Animated cars 🚧 in progress

Plan: [CAR_ANIMATION_PLAN.md](CAR_ANIMATION_PLAN.md).

- **20a, rolling wheels ✅ done:** tread slides over the tyres already drawn into every body
  (a shader, no new art), backwards in reverse, rear wheels locked on the handbrake, smeared at
  top speed, ghosts included. Tyre positions for all 70 bodies found by
  `tools/comfy/wheel_rects.py`; the Bubble Car's tyres hardly show, so it has none.
- 20b, steering front wheels — optional, only if 20a is not enough.
- Extras — body lean when drifting, a squash on wall hits, flickering rocket flames.

---

## Phase 20 — Boats: racing on water ✅ done

A second racing game beside the cars (DESIGN.md §20), asked for on 2026-10-06. It has boats
of different kinds, water courses, its own Boat Dock, and the Splash Cup. Coins and stickers
are shared with the cars.

- **Gate A: design and mockups.**
  - DESIGN §20.
  - Four course layouts, `boat_01`–`boat_04`, drawn by `track_layout.py` from water themes.
    They are about 1.5× the car tracks, each with two alternative paths (branches).
  - The water look probe and theme sheet: `water_probe.py`.
  - The Boat Dock and title layouts.
  - Everything is in `docs/mockups/boat/` and `docs/mockups/boat_0N_layout.png`.
- **Gate B: art.**
  - Nine boat sprites and their paint jobs, using the frozen recipe.
  - Water theme tiles, buoys and the channel texture.
  - Props: ramp, logs, rocks, reeds, lily pads, shipwreck, lemon slices, bridges.
  - Motor, splash, wave and horn sounds.
  - Two music pieces.
- **Gate C: code** (built 2026-10-06; DESIGN.md §20.7–20.8). All boat courses raced headless
  with every kind of boat, and the whole suite passes.
  - `Boat extends Car`.
  - `vehicle_scene` on `TrackConfig`.
  - Water surfaces, currents, ramps and logs in the track builder and `Track`.
  - The Boat Dock as a mode of the garage screen.
  - CARS / BOATS on the title.
  - The Splash Cup.
  - Save schema 4.
  - `tests/boat_test.gd`, plus the whole suite to prove the cars are unchanged.
  - A balance pass.

## Phase 21 — The island: harbour and ocean in Free Drive 🚧 Gate C

The town becomes an island (asked for on 2026-10-06; it needs Phase 20's boats and water).

- The ring of trees at the town's edge gives way to a beach, a shoreline and an ocean all round.
- A **harbour** building on the coast has a pier. Driving onto its pad swaps the car for the
  boat equipped in the Boat Dock. Sailing back to the mooring swaps back.
- At sea: coin trails, a lighthouse, islets with a ramp, buoys, dolphins and seagulls, and
  sailboats.
- The shoreline stops cars at the water and boats at the land.
- It goes through the same three gates, with DESIGN §21 written at Gate A.
- **Gate A: design and mockups** (approved 2026-10-06): DESIGN §21, and
  `docs/mockups/island/`, drawn by `tools/layouts/island_probe.py` from photos of the running
  game: the island overview, the harbour at game scale, and the two swap views.
- **Gate B: art and sound** (approved 2026-10-06): the harbour building (a Kontext edit of
  its block sketch), lighthouse, sailboat, dolphin, seagull and mooring post; wet sand, sea,
  open sea and pier planks; the swap bell, a seagull and a dolphin. DESIGN §21.6.

---

## Ideas parked

Not planned, but worth keeping in mind:


- **Track editor for the child** — place pieces on a grid and race on it. Delightful but large.
- **Weather** — rain on any track (puddles = low-grip patches, wipers on the HUD).
- **Collectable coins on the track** — coins lying on the racing line, adding to the payout.
- **Car customisation beyond paint** — stickers and spoilers on the car itself.
- **Touch controls** — only if the game ever leaves the PC.

## Open questions

1. Should the Phase 10 roster be the six proposed cars, or does Vicky have favourites to include
   (a specific animal, colour, vehicle)?
2. Should cups unlock by finishing (current proposal) or by placing third or better?
