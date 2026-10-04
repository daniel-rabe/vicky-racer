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

## Phase 13 — Music

**Art gate (audio):** candidate tracks per piece, rendered with Stable Audio 3 medium (or ACE-Step,
also installed — to be compared in a short bake-off like the SFX one), picked by listening.

1. **Pieces** — title / garage theme, one race theme per track theme, a short standings sting and
   the podium fanfare. Loopable race themes (the same cross-fade loop cutter as the SFX, with
   bar-aligned loop points).
2. **`MusicManager`** in the main shell — cross-fades between pieces on screen changes, ducks under
   the countdown, and gets slightly faster/brighter on the last lap (a second "final lap" stem or a
   pitch/tempo nudge).
3. **Music volume** from the Phase 9 settings.

**Done when:** every screen has music, loops are seamless (the seam check from `generate_sfx.py`),
and nothing plays under the headless dummy driver.

---

## Phase 14 — Trophy shelf and stickers

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

## Phase 15 — Two players, split screen

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

## Phase 16 — Time trial and ghosts

1. **Time trial** — the player alone, best lap per track and car, from the track select screen.
2. **Ghosts** — record the player's position and rotation every physics tick of the best lap
   (compact: ~30 s × 60 Hz × 3 floats), replay it as a translucent car. Saved per track.
3. **Developer ghosts** — a ghost recorded by the autopilot at full pace shipped with each track,
   as a target to beat.

**Done when:** a ghost replays the recorded lap to within a pixel (headless test), and survives a
save/load.

---

## Phase 17 — Release build

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

## Ideas parked

Not planned, but worth keeping in mind:

- **Track editor for the child** — place pieces on a grid and race on it. Delightful but large.
- **Weather** — rain on any track (puddles = low-grip patches, wipers on the HUD).
- **Collectable coins on the track** — coins lying on the racing line, adding to the payout.
- **Car customisation beyond paint** — stickers and spoilers on the car itself.
- **Touch controls** — only if the game ever leaves the PC.

## Open questions

1. Is two-player split screen wanted early (it changes how HUD and cameras are built), or is the
   order above right?
2. Should the Phase 10 roster be the six proposed cars, or does Vicky have favourites to include
   (a specific animal, colour, vehicle)?
3. Should cups unlock by finishing (current proposal) or by placing third or better?
