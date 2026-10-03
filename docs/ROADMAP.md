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

## Phase 10 — More cars

Today a *drift setup* is both how the car drives and what it looks like. Keep that — one choice is
easier for a child than "car" plus "setup" — but call them **cars** in the garage and grow the
roster, and let the opponents drive them too.

**Art gate:** a candidate sheet per new car (generated top-down, Kontext recolour for card art, as
in Phase 3), plus a garage mockup showing paging between card pages.

1. **Six new cars**, each a distinct trade so no purchase is wasted. Proposed:

   | Car | Character | Price |
   | --- | --- | --- |
   | Monster Truck | Big, very grippy, slow — ploughs through grass and sand with almost no slowdown | 300 |
   | Police Car | Balanced and quick; a siren light flashes when it drifts | 350 |
   | Ice-Cream Van | Slow and heavy, plays a jingle on the horn | 200 |
   | Formula | Highest top speed, needs braking, little grip on grass | 700 |
   | Bubble Car | Tiny, darts into corners, slides on everything | 300 |
   | Dragon | The top prize: fast, slidey, leaves fire-coloured skid marks | 1000 |

2. **Surface multipliers per car** — `DriftSetup` gains `offroad_mult` (how much grass and sand
   slow it), so the Monster Truck has a real reason to exist. Clamped like everything else.
3. **Per-car effects** — `DriftSetup` gains optional `skid_colour`, `engine_pitch` and a `horn`
   sound; skid marks and car audio read them.
4. **Horn** — a new action (gamepad Y in race / H on keyboard). Pure fun, no gameplay effect.
5. **Paint shop** — free colour choice per owned car from a palette of 6 (Kontext recolours made at
   build time, like the opponents). Children love choosing a colour; it costs nothing to balance.
6. **Garage paging** — 3 × 2 pages with shoulder buttons / Q E, a page dot indicator.
7. **Opponents drive the roster** — `TrackConfig` lists a car per opponent; colours come from the
   paint shop palette, so the player's car stays unique (the arrow marker stays regardless).
8. **Economy** — owning everything goes from 1,450 to ~4,300 coins. Raise nothing; tournaments
   (Phase 12) and track first-finish bonuses add income. Re-run the economy pacing table.

**Done when:** `balance_report.py` covers all 12 cars at three paces and no car wins the clean-pace
column by more than ~3 s; the race-setup test checks a new car's body, handling and skid colour.

---

## Phase 11 — Track pipeline and three new tracks

Track 01 is defined once in [`tools/layouts/track_layout.py`](../tools/layouts/track_layout.py) and
built by `track/build/`. Before adding tracks, make that one pipeline produce any track from a
small data file, then use it for three new ones.

**Art gate:** for each track, a layout diagram (as [`mockups/track_01_layout.png`](mockups/track_01_layout.png))
and a style frame for its theme generated with the frozen recipe; new ground fills and props
through candidate sheets.

1. **Layouts as data** — `tools/layouts/tracks/<id>.json`: control points, road width, grid slot,
   checkpoint, surface regions, prop placements. One script builds the diagram, the points file and
   the `.tscn` for any of them. Track 01 is migrated first and must come out identical (track test).
2. **Themes** — a `TrackTheme` resource: ground fills, kerb colours, prop set, music (Phase 13),
   ambient sound. Track 01 becomes the `meadow` theme.
3. **Three new tracks**, each teaching something:

   | Track | Theme | New thing | Shape |
   | --- | --- | --- | --- |
   | Sunny Beach | sand, palm trees, beach balls | wide road, lots of sand to slide in — easy, the first unlock | long sweeping oval |
   | Snowy Peak | snow, pine trees, snowmen | **ice patches**: a new surface with very low grip but full speed — drift heaven | figure-of-eight with a bridge |
   | Toy Town | streets, houses, traffic cones | tighter corners, **boost pads** that give a short speed burst | city blocks, 90° corners |

4. **New surfaces** — `ice` (speed 1.0, grip 0.35) and `boost` (a pad, not a surface: an `Area2D`
   that sets a short `boost_mult`, emitting `CAR_boosted`). Added to `Track.SURFACES` and the effects
   (white sparkles on ice, a whoosh on boost).
5. **Figure-of-eight crossing** — the bridge needs two draw layers and collision layers that swap
   when a car passes the crossing; this is the hardest technical item in the roadmap and can be
   swapped for a simpler shape if it fights back.
6. **Track select** — a screen between garage and race: track cards with the minimap shape, best
   lap and a lock. Tracks unlock by finishing the previous one (any position), never by winning.
7. **AI** — check every track with `race_test` and `balance_report.py`; per-track opponent skills in
   each `TrackConfig`.

**Done when:** four tracks are raceable, each passes the race test with zero AI rescues, and the
track test proves Track 01 rebuilds identically from its JSON.

---

## Phase 12 — Tournament mode

A **cup** is a set of races in a row with points, standings and a trophy at the end.

**Art gate:** cup-select, standings and podium-ceremony layouts; three trophy illustrations
(bronze / silver / gold) and a cup icon per cup, generated with the frozen recipe.

1. **`CupConfig`** resource — name, icon, list of `TrackConfig`s, laps per race, opponent cars and
   skills. Two cups to start: **Sunshine Cup** (Meadow, Beach, Toy Town) and **Snowflake Cup**
   (Beach, Snowy Peak, Meadow reversed), the second unlocked by finishing the first.
2. **Reverse tracks** — every track drivable backwards by flipping the racing line; doubles the
   content for free. Lap validation already works in either direction (checkpoint then finish).
3. **`CupManager`** in the main shell (next to `GarageManager`): current cup, race index, points
   table, persisted between screens. Signals `CUP_started`, `CUP_race_finished(standings)`,
   `CUP_finished(standings, trophy)`.
4. **Points** — 10 / 7 / 5 / 3, all non-zero so a child always scores. Ties go to the better last
   race.
5. **Standings screen** between races: the four cars with points counting up, then NEXT RACE.
6. **Podium ceremony** after the last race: the top three cars on a podium, confetti, fanfare,
   then the trophy flies to the shelf (Phase 14). Third or better earns that cup's trophy colour;
   finishing the cup at all earns a participation ribbon — *nobody is ever told they lost*.
7. **Payout** — normal per-race coins plus a cup bonus (gold 300 / silver 200 / bronze 150 /
   finished 100).
8. **Saving mid-cup** — the cup state is saved after each race, so closing the game does not lose
   a half-finished cup; the title screen offers CONTINUE CUP.

**Done when:** a headless cup test runs a full cup on autopilot, checks points, standings order,
the trophy awarded, the payout and the mid-cup save/resume.

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
