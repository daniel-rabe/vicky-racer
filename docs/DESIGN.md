# Vicky Racer — Design Document

A 2D top-down arcade racer for a young child, built in **Godot 4.7** (Forward+ renderer). The
player races three AI cars around tile-built circuits, earns coins by finishing, and spends them in
a garage on drift setups that change how the car handles. All art is generated locally with
ComfyUI from a single frozen recipe.

This document was written ahead of the code, with every system marked **(not implemented)** until
it landed. All of v1 is now built — the last markers came off with Phase 8 (effects, sound and the
balance pass) — and the document describes the game as it is. Mockups referenced here live in
[`mockups/`](mockups/); every generated image there is reproducible from
[`mockups/seeds.json`](mockups/seeds.json).

---

## 1. Design pillars

| Pillar | What it means in this build |
| --- | --- |
| **Forgiving by construction** | The car *cannot* spin out — steering rotates the car directly instead of applying torque. Walls slide you along rather than stopping you. Grass slows you but never ends your race. Nobody is ever told they lost. |
| **Drift is the fun** | Handling splits forward and sideways grip, so the car slides through corners and the handbrake kicks the tail out on demand. The garage is a menu of different answers to "how slidey?". |
| **Readable at a glance** | Bars instead of numbers, big position and lap readouts, a world-up camera that never rotates, four racers in four primary colours. A child who cannot read yet can still play. |
| **One good track before many** | A single hand-designed circuit, tuned until it is fun, before any second track is considered. |

## 2. Core loop

```
   ┌────────────────────────────────────────────────────────────────┐
   │                                                                │
   ▼                                                                │
 GARAGE ──► GRID ──► 3·2·1·GO ──► RACE 3 LAPS ──► RESULTS ──► COINS ─┘
 (buy /     (4 cars,  (cars       (drift, pass,    (order,     (paid by
  equip      player    frozen)     minimap,         best lap)   position,
  a drift    last-but-                position)                  generous
  setup)     one)                                                floor)
```

0. **Title.** The logo and PLAY / SETTINGS / QUIT over a live race of four AI cars.
1. **Garage.** Browse six drift-setup cards with a gamepad or keyboard. Buy what you can afford,
   equip what you own, press **RACE!**.
2. **Grid.** Four cars on a staggered two-wide grid behind the start/finish line.
3. **Countdown.** A big 3 · 2 · 1 · GO! Cars are frozen until GO.
4. **Race.** Three laps. A lap only counts if the mid-lap checkpoint was crossed.
5. **Results.** Always celebratory. The finishing order slides in, then the coin payout counts up.
6. **Back to the garage** — or straight into **RACE AGAIN**, focused by default.

## 3. Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Steer | ← → or A D | Left stick X (analog) |
| Accelerate | ↑ or W | RT or A |
| Brake / reverse | ↓ or S | LT or B |
| Handbrake (drift) | Space | X |
| Confirm (menus) | Enter | A |
| Back (menus) | Esc | B |
| Race from garage | R | Y |
| Pause (race) | Esc | Start |
| Horn (race) | H | Y |
| Paint the focused car (garage) | C | X |
| Turn the garage page | Q / E | LB / RB |

Escape and B also go back from the garage to the title. In a race, Escape pauses instead of
leaving: one wrong button must never throw away a race (§10).

Both keyboard layouts are always live, so two hands can find the controls without being taught.
Steering reads `Input.get_axis`, which gives analog steering on a stick for free. Menu glyphs swap
between keyboard and gamepad depending on which was used last.

### 3.1 Assists

Two switches on the settings screen, both off by default, both applied live by
[`player_input.gd`](../actors/car/player_input.gd):

- **AUTO GO** — the car cruises at 65 % of its top speed with no pedal held, so a very young child
  only has to steer. Holding accelerate still gives full speed, and braking still brakes.
- **STEER HELP** — steers toward the road ahead: fully while the child is not steering, as a gentle
  nudge (30 %) on top of their steering when they are. It keeps whatever lane the child is in and
  only pulls toward the middle near the edge of the road.

Both on with no input at all, the car laps Track 01 without leaving the road or touching a wall,
and finishes **3rd** — the assists help, they do not race. At 80 % cruise it won outright, which
made it an autopilot; 65 % was chosen so that pressing the pedal still pays
([`tests/assist_test.gd`](../tests/assist_test.gd)).

## 4. Handling model

The car is a `CharacterBody2D` that points **+X**. Every physics frame:

```
forward = Vector2.RIGHT.rotated(rotation)
speed   = velocity.length()

# Steering is input-driven ROTATION, scaled by SIGNED forward speed.
# Because rotation comes from input and not from torque, the car cannot spin out;
# signed speed makes reversing steer the natural way round.
rotation += steer * max_steer_rate * clamp(forward_speed / steer_speed_ref, -1, 1) * delta

# Throttle acts along forward only. Braking below 40 px/s becomes reverse,
# at reverse_power_fraction of engine power, capped at max_reverse_speed.
velocity += forward * accel * delta

# Drift: split velocity and damp each part with its own coefficient.
# exp() is the exact form of per-frame damping and can never overshoot.
fwd_v = forward * velocity.dot(forward)
lat_v = velocity - fwd_v
grip  = (handbrake_lateral_grip if handbrake else lateral_grip) * surface.grip_mult
velocity = fwd_v * exp(-forward_drag * delta) + lat_v * exp(-grip * delta)

# Over the speed limit (e.g. just left the road) the car slows at 1500 px/s², not instantly.
move_and_slide()   # on a fresh wall hit: velocity *= (1 - wall_speed_scrub), keep the slide
```

Implemented in [`actors/car/car.gd`](../actors/car/car.gd). The promises above are checked by
[`tests/handling_test.gd`](../tests/handling_test.gd) — it cannot spin out (even on Banana with
the handbrake), cannot turn on the spot, the handbrake at least doubles the slide, walls slide you
along, grass slows you gradually, and every setup resolves within the clamps:

```bash
Godot_v4.7.1-stable_win64_console.exe --path . --headless --fixed-fps 60 res://tests/handling_test.tscn
```

- **High `lateral_grip`** — the car goes where it points. **Low** — it keeps travelling sideways
  after it turns, which is the drift.
- The **handbrake** swaps in a much lower grip to kick the tail out on demand.
- **Speed-scaled steering** stops the car pirouetting on the spot and keeps it calm at speed.
- `CAR_drift_started` / `CAR_drift_ended` fire when `lat_v.length()` crosses a threshold; skid
  marks and the drift sound hang off those signals (§4.3).

### 4.1 `CarConfig` — the base car

One `Resource` holds the base values, editable in the inspector while the game runs. Starting point:

| Field | Value | Unit |
| --- | --- | --- |
| `engine_power` | 1400 | px/s² |
| `brake_power` | 2200 | px/s² |
| `max_speed` | 1100 | px/s |
| `max_steer_rate` | 3.2 | rad/s |
| `steer_speed_ref` | 350 | px/s — full steering authority from this speed up |
| `forward_drag` | 0.6 | 1/s |
| `lateral_grip` | 9.0 | 1/s |
| `handbrake_lateral_grip` | 1.8 | 1/s |
| `wall_speed_scrub` | 0.15 | fraction of speed lost per wall hit |

### 4.2 `DriftSetup` — what the garage sells

A `DriftSetup` is a `Resource` of **multipliers over** `CarConfig`, never replacement values. Because
they multiply a sane base and the results are clamped, no setup can produce nonsense physics, and
none is a strict upgrade — each is a different trade.

Twelve cars, in garage order (prices rise left to right, two pages of six):

| Car | Grip × | Handbrake grip × | Engine × | Top speed × | Steer × | Off road × | Bars G / S / S | Price | Extras |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Starter** | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 0.7 / 0.4 / 0.5 | owned | |
| **Grippy** | 1.5 | 1.6 | 0.95 | 0.95 | 1.05 | 1.0 | 0.95 / 0.15 / 0.45 | 100 | |
| **Ice-Cream Van** | 1.1 | 1.0 | 0.85 | 0.88 | 0.95 | 1.0 | 0.75 / 0.3 / 0.3 | 200 | horn plays a jingle |
| **Slider** | 0.55 | 0.6 | 1.0 | 1.0 | 1.15 | 1.0 | 0.3 / 0.9 / 0.5 | 250 | |
| **Rocket** | 0.9 | 1.0 | 1.25 | 1.2 | 0.8 | 1.0 | 0.55 / 0.45 / 0.9 | 250 | |
| **Kart** | 1.2 | 1.0 | 1.1 | 0.85 | 1.35 | 1.0 | 0.8 / 0.35 / 0.35 | 250 | |
| **Monster Truck** | 1.4 | 1.3 | 0.9 | 0.9 | 0.9 | **0.2** | 0.9 / 0.2 / 0.4 | 300 | deep engine, air horn; grass barely slows it |
| **Bubble Car** | 0.6 | 0.7 | 1.15 | 0.92 | 1.4 | 1.0 | 0.35 / 0.85 / 0.4 | 300 | high-pitched engine |
| **Police Car** | 1.05 | 0.8 | 1.1 | 1.08 | 1.05 | 1.0 | 0.7 / 0.5 / 0.65 | 350 | siren lights flash while drifting, siren horn |
| **Banana** | 0.45 | 0.5 | 1.3 | 1.25 | 1.0 | 1.0 | 0.2 / 1.0 / 1.0 | 600 | |
| **Formula** | 1.0 | 0.9 | 1.2 | 1.2 | 0.95 | **1.5** | 0.6 / 0.4 / 1.0 | 700 | fastest on straights; must brake, hates grass |
| **Dragon** | 0.55 | 0.6 | 1.2 | 1.2 | 1.1 | 1.0 | 0.3 / 0.9 / 0.95 | 1000 | fire-coloured skid marks and smoke, roar horn |

Resolved values are clamped — `lateral_grip` never below 3.0, `max_speed` never above 1500 px/s,
and however bad a car is off road, grass and sand keep at least 25 % of its speed and grip — so
even Banana stays drivable and the Formula never gets stuck.

**Off road** (`offroad_mult`) scales how much grass and sand slow the car and loosen its grip: the
Monster Truck keeps ~90 % of its speed on grass where the Starter keeps 55 %, the Formula ~43 %.
Each car also brings its own **skid and smoke colour, engine pitch and horn** (`DriftSetup`'s
"Look and sound" group); H / gamepad Y sounds the horn in a race — pure fun, no effect.

The new cars are Kontext edits of the Starter car, like the Phase 5 setups, so all twelve share
one silhouette scale and the frozen look; candidates and picks are in
[`mockups/candidates/`](mockups/candidates/) (`card_monster.png` … `card_dragon.png`). Two needed a
second prompt: the first Monster Truck was red with knobbly tyres, too close to Grippy (now purple
with green flames), and the first Bubble Car came out in perspective (now a round car with a
central dome).

**A setup also changes how the car looks:** in the race the player drives the car from its garage
card — knobbly tyres for Grippy, light-blue swirls for Slider, boosters for Rocket, the go-kart, the
banana car ([`screenshots/setup_cars.png`](screenshots/setup_cars.png)). Setups were first
handling-only, which left a child who bought Banana still driving the plain red car. Because the
player's car can now share a colour with an opponent (Banana and Yellow), a small white arrow
always floats above the player's car. The three **bar values** are authored, not computed: they describe how
the setup *feels*, which is what the garage needs to communicate.

### 4.3 Feedback: marks, puffs, shake and sound

Drift is the fun, so a drift has to be *seen and heard* — the payoff for buying a slippery setup.

![Skid marks, tyre smoke and grass dust](screenshots/drift_effects.png)

| Effect | Trigger | Built in |
| --- | --- | --- |
| **Skid marks** — two dark lines from the rear wheels, fading out 6 s after the drift, at most 80 kept | `CAR_drift_started` / `_ended`, any car | [`actors/effects/skid_marks.gd`](../actors/effects/skid_marks.gd), one node per race between the track and the cars, so marks lie under every car |
| **Tyre smoke** — white puffs while drifting on the road | the car's drift state | [`actors/car/car_effects.gd`](../actors/car/car_effects.gd) |
| **Dust** — earth-coloured on grass (green would vanish against it), sand-coloured on sand | `CAR_surface_changed` | same; the puff texture is a generated soft disc, no art file |
| **Rolling wheels** — tread slides over the tyres drawn into each body: backwards in reverse, rear pair locked on the handbrake, smeared flat at top speed; ghosts roll too, the Bubble Car (tyres hardly show) does not | every physics tick, from the car's forward speed | [`actors/car/rolling_tread.gd`](../actors/car/rolling_tread.gd) and its shader; tyre rectangles per body in [`game/configs/car_wheels.gd`](../game/configs/car_wheels.gd), generated by [`tools/comfy/wheel_rects.py`](../tools/comfy/wheel_rects.py) ([plan](CAR_ANIMATION_PLAN.md)) |
| **Wall shake** — the view jolts by up to 9 px and settles within a second; a bump to feel, not a jolt to frighten | `CAR_wall_hit` for the camera's own car | [`actors/car/chase_camera.gd`](../actors/car/chase_camera.gd), added to the rig's position so physics interpolation still smooths it |
| **Engine** — one steady loop, pitch from 0.6× at rest to 1.5× at top speed, a touch higher under throttle | every frame | [`actors/car/car_audio.gd`](../actors/car/car_audio.gd), positional: opponents are heard near the camera and fade with distance |
| **Tyre squeal** — a loop that fades in with sideways speed | the car's drift state | same |
| **Bump** — a soft thump, louder for harder hits | `CAR_wall_hit` | same |
| **Beeps** — three low beeps and a high GO | `RAC_countdown_tick` | [`game/managers/sound_manager.gd`](../game/managers/sound_manager.gd), in the main shell |
| **Fanfare**, **coin chime**, **menu click** | `RAC_race_finished`; `PRO_setup_purchased` and the results count-up; menu focus moving | same, and [`ui/results/results_screen.gd`](../ui/results/results_screen.gd) |

[`tests/effects_test.gd`](../tests/effects_test.gd) checks the visual effects headlessly. Sounds
are skipped under the dummy audio driver of headless runs: it never mixes, so a played sound would
never finish and be reported as leaked at exit. Where the sounds come from: §11.2.

## 5. Scale

| Thing | Size | Why |
| --- | --- | --- |
| Tile | 128 px | Large enough that generated textures keep their character; a 48 × 28 map stays manageable in the editor |
| Road | 3 tiles (384 px) | Room for two cars side by side plus a mistake |
| Car sprite | 128 × 72 px, facing +X | Godot 2D's zero rotation; reads clearly against a 384 px road |
| Car collision | 110 × 60 px rectangle | Slightly inside the sprite so contact looks fair |
| Viewport | 1920 × 1080, `canvas_items` / `expand` | Already set in `project.godot` |
| Camera zoom | 0.92, fixed | About 16 × 9 tiles visible. Close enough to match the chosen style frame, where cars read at ~130–160 px; the camera's 260 px lead toward the direction of travel shows about a second of road ahead at top speed. A speed-dependent zoom-out was dropped: changing zoom while driving defeats physics interpolation and made the view judder (see below) |

### 5.1 Smooth motion on fast monitors

Physics runs at 60 Hz, but monitors refresh at 100–165 Hz. Without help the car and camera only
move on physics ticks, so on a 100 Hz screen the view moves on three frames in five and stands
still on the other two — a judder that reads as flicker. The fix is Godot's **physics
interpolation** (`project.godot`), which draws everything between ticks. It only smooths node
*positions*, so the chase camera ([`actors/car/chase_camera.gd`](../actors/car/chase_camera.gd))
is built from positions alone: a rig node holds the lead, the Camera2D has no smoothing, and the
zoom is fixed. Anything teleported (a reset, the start grid) calls
`reset_physics_interpolation()` so it does not glide.

[`tools/dev/motion_check.py`](../tools/dev/motion_check.py) measures this on rendered frames
(100 fps against 60 Hz physics, tracking a hay bale): frame-to-frame wobble of the view went from
**17.8 px** without interpolation to **0.57 px** with it — the same as running physics at 100 Hz.

### 5.2 Performance

[`tests/perf_probe.gd`](../tests/perf_probe.gd) measures a full race with every car on
autopilot. Headless at a fixed 60 fps (`-- --autopilot --bench`), wall time per frame is the
whole CPU cost of simulating the race; with a window it reports frame rate, draw calls and
objects.

| Measure (RTX 5070 Ti machine) | Before the pass | After |
| --- | --- | --- |
| CPU per simulated frame (scripts + physics) | 415 µs | **234 µs** — 1.4 % of a 60 Hz frame |
| Windowed, vsync off | 1,940 fps | 2,190 fps |
| Draw calls / objects | ~40 / stable | unchanged |
| Race load (track, road, cars) | — | 18 ms |

Three changes, each measured on its own:

1. **Racing line baked at 20 px**, not Godot's default 5. Every closest-point search walks
   every baked point; a quarter of the points made each search ~11 → 3 µs. On Track 01's
   tightest bend the chord error is under a quarter pixel, and the balance table did not move.
2. **Each car measured once per frame.** The track (physics priority −2, before anyone
   else) searches the line once per car and caches progress and distance; the race, the AI and
   steering help read `Track.progress_of()` / `distance_of()` instead of searching again.
3. **Minimap line cached in map space**, rebuilt only on resize. Converting all 200 points every
   frame was the most expensive script in the race (71 µs).

The game is far inside its budget even on this fast machine; the margins are for the slower
laptop a child is likely to play on.

## 6. Architecture

### 6.1 Event bus

As in Vicky's Game, systems never hold references to each other. `game/event_system.gd` is the
single autoload (`EventSystem`) and declares every cross-system signal. Managers `connect` in
`_enter_tree()`; emitters call `EventSystem.<SIGNAL>.emit(...)`.

| Prefix | Domain | Signals |
| --- | --- | --- |
| `RAC_` | Race | `countdown_tick(n)`, `race_started()`, `lap_completed(racer, lap, lap_time)`, `final_lap_started()`, `positions_updated(order)`, `race_finished(results, track_id)`, `time_trial_finished(track_id, setup_id, lap_times, ghost)` |
| `CAR_` | Car | `drift_started(car)`, `drift_ended(car, duration)`, `surface_changed(car, surface)`, `wall_hit(car, impact_speed)` |
| `PRO_` | Progression | `state_requested()`, `state_changed(state)`, `buy_requested(id)`, `equip_requested(id)`, `coins_changed(total)`, `coins_awarded(amount, breakdown)`, `setup_purchased(id)`, `setup_equipped(id)`, `purchase_refused(id, reason)`, `sticker_earned(id)` |
| `CUP_` | Cups | `state_requested()`, `state_changed(state)`, `start_requested(id)`, `continue_requested()`, `progress_changed(progress)`, `finished(id, standings, trophy)` |
| `PLY_` | Players | `state_requested()`, `state_changed(state)`, `two_player_requested()`, `join_requested(device, setup_id)`, `car_requested(index, setup_id)`, `opponents_requested(on)` |
| `UI_` | Screens | `show_message(text, duration)`, `screen_requested(name)`, `settings_requested()`, `settings_changed(settings)`, `setting_change_requested(key, value)`, `music_requested(piece)` |

Screens never reach into managers. Following Vicky's Game's inventory pattern, a screen emits
`PRO_state_requested` and `GarageManager` answers synchronously with `PRO_state_changed`, carrying
the whole garage state: coins, owned and equipped setups, best laps and the last race. Buying and
equipping are requests (`PRO_buy_requested`, `PRO_equip_requested`); the manager decides.

Each `RAC_race_finished` result is a Dictionary: `name`, `body` (car sprite path), `is_player`,
`position`, `time`, `best_lap`.

### 6.2 Scenes and managers

```
main.tscn  (persistent shell — never unloaded)
├── GarageManager        wallet, ownership, equipped setup, last race; pays out on RAC_race_finished
├── SettingsManager      volume, fullscreen, assists, difficulty; applies and saves every change
├── SoundManager         beeps, fanfare, coin, menu clicks (runs while paused)
└── ScreenSlot           swaps on UI_screen_requested(&"title" | &"garage" | &"race" | &"results"):
    ├── title_screen.tscn     logo + menu over a live attract-mode race; SettingsPanel
    ├── garage_screen.tscn
    ├── race.tscn
    │   ├── Track (track_01.tscn)
    │   ├── SkidMarks
    │   ├── RacerSpawner      places 4 cars on the grid
    │   ├── RaceManager       countdown, laps, positions, rubber-banding, finish
    │   ├── RaceHUD + Minimap
    │   └── PauseMenu         pauses the tree; RESUME / RESTART / SETTINGS / GARAGE
    └── results_screen.tscn
```

The managers live in the shell rather than becoming more autoloads, keeping to the one-autoload
rule while still surviving every screen swap. Changing screen always unpauses the tree.

### 6.3 Drivers

`car.gd` exposes three plain fields — `steer_input`, `throttle_input`, `handbrake` — and knows
nothing about who sets them. `player_input.gd` and `ai_driver.gd` are interchangeable children that
write into those fields. The same car scene is used for all four racers.

## 7. Tracks

Seven tracks in seven themes, raced in this order; each opens when the one before it has been
finished, in any place (§7.6).

| # | Track | Theme | What it adds | Lap (AI) | Layout | Built |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Meadow Loop** | grass, sand traps, trees | a **figure-of-eight over a bridge** | 22,600 px, ~24 s | [`track_01_layout.png`](mockups/track_01_layout.png) | [`screenshots/track_bridge.png`](screenshots/track_bridge.png) |
| 2 | **Sunny Beach** | sand, dunes, palms, parasols, beach balls | a wide (3.5-tile) flowing loop: the easy one, no crossing | 20,000 px, ~22 s | [`track_02_layout.png`](mockups/track_02_layout.png) | [`screenshots/track_beach.png`](screenshots/track_beach.png) |
| 3 | **Snowy Peak** | snow, ice ponds, pine trees, snowmen | a **mountain bridge** over its own hairpin loop, **ice on the road** at three bends | 28,000 px, ~31 s | [`track_03_layout.png`](mockups/track_03_layout.png) | [`screenshots/track_snow.png`](screenshots/track_snow.png) |
| 4 | **Toy Town** | lawns, sandpits, toy houses, traffic cones | a **flyover** across the main street, city corners, three **boost pads** | 25,600 px, ~27 s | [`track_04_layout.png`](mockups/track_04_layout.png) | [`screenshots/track_town.png`](screenshots/track_town.png) |
| 5 | **Jungle Run** | jungle, mud puddles, jungle trees, flowers, boulders | the twistiest: S-bends, a hairpin, a loop over a **log bridge** across its own back straight | 25,100 px, ~28 s | [`track_05_layout.png`](mockups/track_05_layout.png) | [`screenshots/track_jungle.png`](screenshots/track_jungle.png) |
| 6 | **Candy Lane** | pink icing, chocolate puddles, lollipops, donuts, cupcakes, gumdrops | a **heart**: two long diagonals with a **boost pad** each, the dip and the tip | 20,400 px, ~22 s | [`track_06_layout.png`](mockups/track_06_layout.png) | [`screenshots/track_candy.png`](screenshots/track_candy.png) |
| 7 | **Moon Base** | moon dust (low grip), craters, rockets, dish aerials, moon rocks | a **loop-the-loop** over a bridge, two **boost pads**, slippery ground off the road | 26,500 px, ~28 s | [`track_07_layout.png`](mockups/track_07_layout.png) | [`screenshots/track_moon.png`](screenshots/track_moon.png) |

Three laps take 65–95 s. The tracks were first built at about half this length (~15 s laps) and
lengthened on request, with bridges where the road crosses itself (§7.7).

### 7.1 Track 01 — Meadow Loop

![Track 01 layout](mockups/track_01_layout.png)

- **64 × 40 tiles** (8192 × 5120 px), a figure-of-eight, lap ≈ **176 tiles / 22,600 px**, about
  **24 s** for the AI — a bit over a minute for three laps.
- The start straight leads up over the bridge, down round the right-hand loop (T1–T3), back under
  the bridge and round the left-hand loop (T4–T6) to the line. Sand traps sit in the corners, where
  mistakes happen.
- The circuit is defined **once**, in [`tools/layouts/tracks/track_01.json`](../tools/layouts/tracks/track_01.json)
  (§7.2). [`tools/layouts/track_layout.py`](../tools/layouts/track_layout.py) writes both this diagram and
  [`mockups/track_01_points.json`](mockups/track_01_points.json), which the game reads to build the
  racing line — so the reviewed layout and the driven track cannot drift apart.

### 7.2 Building the track: spline road over a tile map

Decided after [`mockups/road_compare.png`](mockups/road_compare.png): tile terrain turns the hairpin
into a jagged octagon, while a road drawn from the spline keeps frame 04's smooth sweep. So the
track is two layers:

- **Ground — a `TileMapLayer`.** Grass, sand traps and decoration, painted by hand in Godot's
  TileMap editor. The fills are the flat procedural textures (§11.1); the grass↔sand edge pieces
  are composited by script from those fills, so every edge matches.
- **Road — built from the spline.** A `Path2D` holds the racing line, defined by the control
  points in `tools/layouts/track_layout.py`. From it the track scene builds, in `_ready()` and as
  an editor tool so it is visible while editing:
  - the asphalt as a `Polygon2D` (the curve offset ±192 px, textured with the asphalt fill);
  - the kerbs as `Line2D`s along both road edges, textured with the kerb strip in tile mode, so
    the red/cream blocks follow every bend at an even spacing — only where the bend is tight;
  - the lane dashes and the chequered start/finish line.

  Moving a control point moves the road, the kerbs, the racing line and the surface detection
  together. Nothing about the road is painted by hand, so it can never disagree with the AI's line.
  Kerbs are continuous strips: gaps under 160 px between tight stretches are bridged and pieces
  under 320 px dropped, so gentle bends at the threshold do not fragment.

**Built:** [`screenshots/track_overview.png`](screenshots/track_overview.png),
[`screenshots/track_grid.png`](screenshots/track_grid.png).

| Piece | File |
| --- | --- |
| Ground tileset: 16 corner tiles, Grass/Sand terrain in Match Corners mode | [`tools/layouts/build_tileset.py`](../tools/layouts/build_tileset.py) → `art/tiles/ground_atlas.png`, `track/ground_tiles.tres` |
| Track logic and road drawing (`@tool`, so the road also shows in the editor) | [`track/track.gd`](../track/track.gd) |
| Scene builder: layout points → `track_01.tscn` (curve, painted sand traps, grid, gates, walls, trees, tyre stacks) | [`track/build/build_track.gd`](../track/build/build_track.gd) |
| Checks: surfaces, progress, grid, gates | [`tests/track_test.gd`](../tests/track_test.gd) |

Inside a ground tile, sand is where the bilinear blend of its four corners exceeds 0.5. The tiles
are drawn with that rule and `Track.surface_at()` tests with it, so what you see is what you drive
on. Neighbouring tiles share corners, so edges continue across tile borders without a seam.

**Every track is data.** A track is a JSON spec in [`tools/layouts/tracks/`](../tools/layouts/tracks/):
map size, road width, control points, where the finish goes (the grid is placed behind it, along
the road), patches of the theme's patch surface, props by kind, and — as fractions of a lap — ice
on the road and boost pads. To change a track, or add one: edit or add its spec, then

```bash
python tools/layouts/track_layout.py            # diagrams + points for every spec
python tools/layouts/theme_art.py               # theme textures (only when themes change)
python tools/layouts/prop_art.py                # drawn props: Jungle, Candy, Moon (only when they change)
Godot_v4.7.1-stable_win64_console.exe --path . --headless res://track/build/build_track.tscn
```

`track_layout.py` also reports how close the road comes to itself and warns below a road width plus
a tile. Migrating Track 01 to a spec reproduced its points file field for field; the rebuilt scene
differs only by its theme and four grid-slot rotations of ~0.002 rad (the Phase 8 performance pass
changed the curve's bake interval in the scene without a rebuild).

Image generation makes none of this geometry — it is exactly what diffusion does worst. Generated
art is limited to the cars, props and UI illustrations.

### 7.3 Surfaces

The car checks what it is on every physics frame:

1. **On the road?** Distance from the car to the racing line (`Curve2D.get_closest_point`) is under
   the road's half-width → asphalt. Kerbs count as asphalt.

The track, not the car, does this: each physics frame it sets the surface multipliers of every
node in the `cars` group and emits `CAR_surface_changed` when a car's surface changes. Cars stay
unaware of tracks.
2. **Otherwise**, the ground tile beneath it, read from the TileSet's custom data layer `surface`.

| Surface | `speed_mult` | `lateral_grip` × | Feel |
| --- | --- | --- | --- |
| Asphalt / kerb | 1.0 | 1.0 | Normal |
| Grass | 0.55 | 0.7 | Slow and a bit loose — get back on |
| Sand | 0.4 | 0.6 | Sticky and slow, but you drive out |
| Beach | 0.6 | 0.65 | Sunny Beach's ground: softer than a sand trap, it is the easy track |
| Snow | 0.6 | 0.55 | Snowy Peak's ground |
| **Ice** | **1.0** | **0.35** | Full speed, almost no grip — drift heaven, never a stop. Ponds off the road, and spans *on* it |
| Jungle | 0.55 | 0.7 | Jungle Run's ground: like grass |
| Mud | 0.4 | 0.55 | Jungle Run's puddles: a sand trap that also slides |
| Candy | 0.6 | 0.65 | Candy Lane's icing: soft, like the beach |
| Chocolate | 0.45 | 0.6 | Candy Lane's puddles: gooey |
| Moon dust | 0.6 | 0.45 | Moon Base's ground: floaty, the car slides wide |
| Crater | 0.45 | 0.45 | Moon Base's craters: deeper dust |

On the road, a span of ice (`Track.ice_spans`, fractions of a lap) overrides asphalt; it is drawn
as translucent sheet ice so the road still reads as road. Each car's off-road ability (§4.2)
softens the off-road surfaces. The map edge is a wall of the theme's prop (tyres, beach balls,
traffic cones): solid, but it slides you along it.

**Boost pads** (Toy Town) are `Area2D`s across the road: driving over one gives 1.2 s of extra push
(1,800 px/s²) and lets the car go 30 % past its top speed, fading over the last third, and emits
`CAR_boosted` (a whoosh). The track test checks a boosted car passes its top speed.

### 7.4 Progress and laps

- **Progress** is distance along the racing line: `progress = laps × lap_length +
  curve.get_closest_offset(position)`. One number per car, sorted every frame for live positions.
- **Lap validation** uses two `Area2D`s: the mid-lap checkpoint must be crossed before the
  start/finish line counts. This blocks reverse driving and cutting across the infield.

### 7.5 Themes

A theme ([`TrackTheme`](../game/configs/track_theme.gd), one `.tres` per theme in `game/configs/themes/`)
is the look and the ground of a track: the ground tiles, which surface is everywhere off the road
(`base_surface`) and which one the painted patches are (`patch_surface`), the road and kerb
textures, the edge-wall prop, and the colour of its card. Its textures come from
[`tools/layouts/theme_art.py`](../tools/layouts/theme_art.py) and
[`themes.json`](../tools/layouts/themes.json): flat procedural fills (snow, ice and beach joined
grass and sand in `pipeline.json`), the kerb strip in the theme's colours, and the 16-tile corner
atlas of base and patch — the same corner rule as Track 01, so surfaces match what is drawn. Toy
Town shares the meadow's tiles. Meadow's outputs are byte-identical to the originals.

| Theme | Base / patch | Kerbs | Wall | Props (generated, picked from four) |
| --- | --- | --- | --- | --- |
| Meadow | grass / sand | red / cream | tyres | tree, tyre stack |
| Sunny Beach | beach / grass dunes | blue / white | beach balls | palm tree, parasol, beach ball |
| Snowy Peak | snow / ice | red / white | tyres | pine tree, snowman |
| Toy Town | grass / sand | yellow / blue | traffic cones | toy house, traffic cone, tree |
| Jungle Run | jungle / mud | orange / yellow | boulders | jungle tree, flower, boulder (drawn by script) |
| Candy Lane | candy / chocolate | mint / white | gumdrops | lollipop, donut, cupcake, gumdrop (drawn by script) |
| Moon Base | moon dust / crater | charcoal / yellow | moon rocks | rocket, dish aerial, moon rock (drawn by script) |

The last three themes' props ([`mockups/props_jungle_candy_moon.png`](mockups/props_jungle_candy_moon.png))
were not generated: ComfyUI was not to hand when they were added. [`tools/layouts/prop_art.py`](../tools/layouts/prop_art.py)
draws each one as a stack of flat shapes, gives every shape a pillowy height from its own blurred
outline and lights the height field from the top left, which gets close to the generated props'
soft clay look; the Starlight Cup's star icon is drawn the same way. Seeded, so a rebuild is
byte-identical. Their FLUX versions can replace them file for file.

Two props needed a second prompt: "seen from directly above" still drew the snowman and the house
from the front, like stickers standing up. Describing the shape from above instead ("a big round
snowball seen from the top as a circle, a black top hat at the centre"; "the roof … no walls and no
door visible") gave true top-down pictures that sit in the world like everything else.

### 7.6 Track select and unlocking

RACE! in the garage opens **PICK A TRACK** ([`screenshots/track_select.png`](screenshots/track_select.png)):
a scrolling row of cards (the focused one kept in view) with the track's shape drawn from its racing line, its name, and the best lap, NEW! or —
while locked — a padlock and "FINISH <the track before>". A track opens when the one before it has
been finished **in any place**: a child is never stuck behind a race they cannot win. The choice is
saved (`selected_track` in the profile; older saves start on the first track), RACE AGAIN on the
results screen re-races it, and every track's first finish pays its +100 bonus. Each track has its
own opponents in its own cars ([`game/configs/tracks/`](../game/configs/tracks/)), always blue,
yellow and green.

The balance report runs per track (`--track`); the race test's "sensible lap" bound scales with
the lap length. On the longer tracks a struggling child reaches the podium with every car on every
track but one pairing: the slowest car driven slowest — the Ice-Cream Van at 0.7 pace — finishes
4th on Meadow Loop, 7.6 s back (3rd elsewhere, up to 9 s back on Snowy Peak). Small pace gaps add
up over longer laps; Easy difficulty is the answer for that child. The top-speed cars (Banana,
Formula, Dragon) win clean races by 3–5 s; the autopilot never pays their slipperiness the way a
child does.

### 7.7 Bridges

Where a track's line crosses itself, one pass goes over the other on a bridge. The spec names the
upper pass (`"bridges": [{"upper_at": 0.13, "length_tiles": 20}]`, the lap fraction where it
crosses); `track_layout.py` finds every crossing, centres the span on that pass, and warns about a
crossing with no bridge or a finish line, checkpoint, boost pad or ice patch on or by one (the
checkpoint moves itself forward off a bridge). It reports the crossing angle: 63–90° on the three
bridges, so the levels clearly read as one road over another.

| Problem | Answer |
| --- | --- |
| Race position at the crossing: the closest point on the line is ambiguous where two passes meet | `Track` measures each car by searching only a short window of the line (±12 baked points, 240 px) around where it was last frame, so a car keeps to its own pass. A full search runs only when a car is new or was moved (a rescue). Also cheaper: CPU per race frame fell from 249 to 208 µs |
| Two levels | A car within a bridge span and on the road is **level 1**: drawn above the deck (`z_index` 2; the deck is 1), on its own physics layer. Drawing switches 120 px (more than half a car) *before* the deck starts and *after* it ends, collisions at the span itself — first built switching both at once, which cut the car in half at both ends of the deck for a frame (reported in play, now checked by the track test). Cars on the two levels never collide; cars on the same level still bump |
| Falling off | Solid **railings** along the high middle of each span, on a layer only level-1 cars collide with, so cars below drive under them. Skid marks laid on a bridge lie on its deck |
| Looking like a bridge | The deck redraws the road above everything below it, with white railings and a shadow on the ground; the AI ignores cars on the other level when choosing its lane |

[`tests/track_test.gd`](../tests/track_test.gd) drives a car over Meadow Loop's bridge (ground →
bridge → ground, its progress never jumping to the other pass), and checks the two levels pass
through each other, the same level still collides, and the railing stops only a bridge car.

The longer tracks moved the save to **schema 3**: best laps from older saves belonged to the short
tracks and are dropped; coins, cars and paint are kept.

## 8. AI and the race

### 8.1 AI drivers

Each AI car runs [`actors/car/ai_driver.gd`](../actors/car/ai_driver.gd), writing the same three
inputs a player would:

1. **Steer** at a point on the racing line 150 px + 0.3 s of speed ahead, shifted sideways into
   its own lane (−70 / 0 / +70 px), so the pack does not drive in single file.
2. **Read the road ahead** — the sharpest bend in the next 250 / 500 / 800 px sets a target speed
   between its straight pace (0.80 + 0.15 × skill of its top speed) and corner pace (0.45 + 0.15 ×
   skill of the *base* car's top speed, times its setup's steering multiplier); it lifts or brakes
   to meet it. Corner speed follows how fast the car turns, not how fast it goes: a Kart carries
   more speed through a bend, a Rocket must lift more. Opponents drive the base car, so for them
   nothing changes; it matters when the player's car is on autopilot for the balance pass (§8.3).
3. **Avoid** — a car close in front pushes it into the other half of the road until clear.
4. **Never strand** — stuck (slow with the throttle down) for 1.2 s, it backs out steering the
   other way; after three back-outs, or 900 px off the line, it is put back on the line. The race
   test expects no rescues in a normal race, and sees none.
5. **Skill** — 0.85 / 0.70 / 0.55 for Blue / Yellow / Green on Track 01
   ([`game/configs/tracks/track_01.tres`](../game/configs/tracks/track_01.tres)).
6. **Their cars** — opponents drive garage cars in their own colour: Blue a blue-painted Police Car,
   Yellow the Banana, Green the Dragon — a preview of what the garage sells. An opponent's car sets
   its handling, acceleration and look, but its **pace comes from the base car**
   (`AIDriver.pace_from_base`), so difficulty does not depend on which car it wears: with pace from
   its own car, a Banana-driving opponent left a child in the Ice-Cream Van 7 s behind. The player's
   autopilot (balance tests) paces from its own car, so each car's speed still shows.

### 8.2 Race flow

[`RaceManager`](../game/managers/race_manager.gd) holds the cars still through 3-2-1-GO, then:

- **Laps** count on the finish line only after the mid-lap checkpoint. The grid is behind the
  line, so the first crossing *starts* lap 1. Lap 1 is timed from GO.
- **Positions** sort finished cars by finish time, the rest by progress (laps × lap length + distance
  past the line; negative on the grid).
- **The race ends when the player finishes** (after a 2.5 s FINISH! moment). Opponents still racing
  get a time from their average pace carried over the distance left, so a child never waits on a
  race that is over for them. Results go out on `RAC_race_finished`; `GarageManager` pays out.
- The player starts **3rd of 4** — something to chase, nobody to lap.

### 8.3 Rubber-banding and the balance pass

Each AI's pace is scaled by how far it is from **where it wants to be**: 1,500 px ahead of that
spot it eases to **60 %**, the same distance behind it pushes to **112 %**, and may then pass its
own top speed by as much (`Car.catch_up_mult`), so a player on a faster setup cannot simply drive
away. Where it wants to be: level with the player for Blue, the best driver; the others hang back
5,000 px per point of skill below 0.85, so Yellow 750 px and Green 1,500 px. The best opponent
always makes the player work for a win, and the weaker two leave room on the podium for a child who
is still learning ([`race_manager.gd`](../game/managers/race_manager.gd)).

These numbers are **Normal**. The settings screen's OPPONENTS switch picks one of three
[`DifficultyConfig`](../game/configs/difficulty_config.gd) resources, which shift every
opponent's skill and retune the band:

| Difficulty | Skill | Ease off / push | Hang back per skill point | Struggling child (0.7) | Clean driving |
| --- | --- | --- | --- | --- | --- |
| Easy | −0.10 | 55 % / 110 % | 6,000 px | 2nd by a few tenths with Starter, wins with the faster setups | wins by ~2 s |
| Normal | — | 60 % / 112 % | 5,000 px | 3rd | wins by ~1 s |
| Fast | +0.10 | 75 % / 115 % | 2,500 px | 4th, 2–6 s back | a close fight for 1st |

Tuned with [`tools/dev/balance_report.py`](../tools/dev/balance_report.py) (`--difficulty`), which races every setup
with the player's car on autopilot at three paces: 1.0 = clean driving, 0.85 = a decent child,
0.7 = a struggling one. Each cell is the player's place and the gap to the winner (negative = the
winning margin). Runs are deterministic, so before and after compare directly.

Before Phase 8 (70 % / 1,800 px, every AI banded level with the player, capped at its own top
speed):

| Setup | 1.0 | 0.85 | 0.7 |
| --- | --- | --- | --- |
| Starter | 2nd +0.2 s | 4th +1.0 s | 4th +2.8 s |
| Grippy | 2nd +0.3 s | 4th +1.4 s | 4th +4.1 s |
| Slider | 2nd +0.1 s | 4th +1.2 s | 4th +3.0 s |
| Rocket | 1st −4.3 s | 1st −0.6 s | 4th +1.1 s |
| Kart | 4th +0.6 s | 4th +2.2 s | 4th +7.1 s |
| Banana | 1st −4.5 s | 1st −0.8 s | 3rd +0.8 s |

Three problems: a decent child came last on every setup but the two fastest; Rocket and Banana won
by over 4 s, because nothing could catch them on the straights; and Kart looked strictly worse, only
because the autopilot ignored its sharper steering. Shipped:

| Setup | 1.0 | 0.85 | 0.7 |
| --- | --- | --- | --- |
| Starter | 1st −0.8 s | 2nd +0.4 s | 3rd +1.4 s |
| Grippy | 1st −0.6 s | 2nd +0.6 s | 3rd +1.5 s |
| Slider | 1st −1.0 s | 3rd +1.0 s | 3rd +1.5 s |
| Rocket | 1st −1.7 s | 1st −0.1 s | 3rd +1.0 s |
| Kart | 1st −0.8 s | 2nd +0.6 s | 3rd +1.3 s |
| Banana | 1st −3.0 s | 1st −0.5 s | 2nd +0.6 s |

Clean driving wins narrowly on anything; a decent child fights for 2nd and 3rd; a struggling child
reaches the podium.

With twelve cars and opponents in roster cars (Phase 10), Normal:

| Car | 1.0 | 0.85 | 0.7 |
| --- | --- | --- | --- |
| Starter | 1st −0.6 s | 2nd +0.6 s | 3rd +1.6 s |
| Grippy | 1st −0.4 s | 2nd +0.7 s | 3rd +1.8 s |
| Ice-Cream Van | 2nd +0.4 s | 3rd +1.3 s | 3rd +2.5 s |
| Slider | 1st −0.7 s | 2nd +0.5 s | 3rd +1.5 s |
| Rocket | 1st −1.3 s | 2nd +0.1 s | 2nd +1.0 s |
| Kart | 1st −0.5 s | 2nd +0.7 s | 3rd +1.5 s |
| Monster Truck | 2nd +0.2 s | 2nd +1.1 s | 3rd +2.4 s |
| Bubble Car | 1st −1.0 s | 2nd +0.5 s | 3rd +1.3 s |
| Police Car | 1st −1.5 s | 2nd +0.1 s | 2nd +1.0 s |
| Banana | 1st −2.6 s | 1st −0.4 s | 2nd +0.8 s |
| Formula | 1st −2.4 s | 1st −0.2 s | 3rd +1.0 s |
| Dragon | 1st −3.3 s | 1st −0.4 s | 2nd +0.7 s |

The Formula first won clean races by 6.2 s and was cut back (top speed 1.3 → 1.2, steering
1.1 → 0.95: fastest on straights, but it must brake for bends); the Dragon by 4.2 s (1.25 → 1.2).
The slow, steady cars (Ice-Cream Van, Monster Truck) are the easy-to-drive end, never last. Setups are worth buying without trivialising the race. The autopilot never
uses the handbrake, so the table cannot show what a slippery setup costs a child in control:
Banana's margin is deliberately the largest because it is also the hardest car to keep on the road.

## 9. Garage and economy

### 9.1 Earning

| Finish | Coins |
| --- | --- |
| 1st | 100 |
| 2nd | 75 |
| 3rd | 60 |
| 4th | 50 |
| First time finishing a track | +100 once |

Owning all twelve cars costs **4,300 coins**: at the ~65 coins a race a decent child earns, a new
car every three to five races early on, and the Dragon as a long-term goal. The cups of Phase 12 add
income on top.

The Phase 8 balance pass left these numbers alone: with the retuned rubber-banding a decent child
finishes 2nd or 3rd (60–75 coins), which keeps the pacing below. The floor is deliberately generous: a child finishing last every time still affords **Grippy**
after two races and a 250-coin setup after about five. Winning just gets there faster. All of
these numbers live in one `EconomyConfig` resource.

### 9.2 Save file

A `ConfigFile` at `user://vicky_racer.cfg`:

```ini
[profile]
schema_version=2
coins=240
owned_setups=PackedStringArray("starter", "slider")
equipped_setup="slider"
completed_tracks=PackedStringArray("track_01")

[best_laps]
track_01=38.90
```

`completed_tracks` records which tracks have paid their one-off first-finish bonus. Schema **2**
(Phase 10) adds a `[paint]` section, car id = colour; version 1 files load as they are and are
written back as version 2.

Loading is defensive: a missing, unreadable or unknown-version file yields a fresh profile instead
of an error, and an unreadable file is kept as `vicky_racer.cfg.bak` rather than overwritten.
Values are sanitised on load — negative coins become 0, Starter is always owned, and an equipped
setup the player does not own falls back to Starter. A broken save must never stand between a
child and the game.

A purchase equips the setup straight away: a child who just bought something wants to drive it.

Implemented in [`game/save_game.gd`](../game/save_game.gd) and
[`game/managers/garage_manager.gd`](../game/managers/garage_manager.gd); checked by
[`tests/economy_test.gd`](../tests/economy_test.gd), which also proves the design promise that two
last places afford Grippy.

### 9.3 Paint shop

Every owned car can be painted, free, as often as the child likes: X / C in the garage cycles the
focused car through **original → blue → yellow → green → purple → pink**, and the card, the preview
and the race car all change. The paint is saved per car. The 57 paint jobs (12 cars × 5 colours,
less the three that already existed as the opponents' recoloured Starter cars) are Kontext
recolours of each car's master, declared in one `paints` section of
[`asset_manifest.json`](../tools/comfy/asset_manifest.json); `generate_assets.py paint-sheet` lays
them all out ([`mockups/candidates/paint_shop.png`](mockups/candidates/paint_shop.png)).
[`Paint`](../game/configs/paint.gd) maps a car and a colour to its card and race body.

## 10. Screens

| Screen | Spec |
| --- | --- |
| Title | [`mockups/title_layout.png`](mockups/title_layout.png) — logo, PLAY / SETTINGS / QUIT over a live attract-mode race (four AI cars on Track 01, no HUD, no engine sounds). Built: [`screenshots/title.png`](screenshots/title.png) |
| Pause | [`mockups/pause_settings_layout.png`](mockups/pause_settings_layout.png) — Esc / Start or the window losing focus pauses the whole tree. RESUME is focused, so pausing twice resumes; B resumes too; RESTART and GARAGE ask SURE? with NO focused. Built: [`screenshots/pause.png`](screenshots/pause.png) |
| Settings | Same spec — SOUND, MUSIC, FULLSCREEN, AUTO GO, STEER HELP, OPPONENTS; one focusable row each, ← → change it. Over the title and over the pause menu. Built: [`screenshots/settings.png`](screenshots/settings.png) |
| Race HUD | [`mockups/hud_layout.png`](mockups/hud_layout.png) — position, lap, timers, speed bar, minimap, countdown. Built: [`screenshots/race.png`](screenshots/race.png), [`screenshots/race_countdown.png`](screenshots/race_countdown.png). The countdown sits above screen centre rather than on it, so it never hides the player's own car |
| Garage | [`mockups/garage_layout.png`](mockups/garage_layout.png) — balance, cards in pages of 3 × 2 (Q / E or the shoulder buttons, or moving off the edge of a page, turns it; `< 1 / 2 >` above the cards), preview with Grip / Slide / Speed bars and, for owned cars, paint swatches. Built: [`screenshots/garage.png`](screenshots/garage.png) |
| Pick a race | RACE / TIME TRIAL switch (§16), a row of track cards (§7.6) and a row of cup cards (§12), each scrolling sideways with the focus. ← → ↑ ↓ choose, A races, B back to the garage. Built: [`screenshots/pick_a_race.png`](screenshots/pick_a_race.png) |
| Standings, podium | §12 |
| Two players | §15 — 2 PLAYERS on the title: the join screen, then PICK A RACE and a split-screen race. Built: [`screenshots/join.png`](screenshots/join.png), [`screenshots/split_screen.png`](screenshots/split_screen.png) |
| Trophy shelf | §14 — the trophy button right of PLAY on the title. Built: [`screenshots/shelf.png`](screenshots/shelf.png) |
| Results | [`mockups/results_layout.png`](mockups/results_layout.png) — finishing order, payout count-up, Race Again. Built: [`screenshots/results.png`](screenshots/results.png) |

Pink annotations on each spec give anchors, sizes and animation timings; they are meant to be
built verbatim with `Control` anchors. All menus are fully navigable with a gamepad alone.

### 10.1 Settings file

`user://vicky_settings.cfg`, separate from the save game: settings belong to the computer and
the person at it, progress belongs to the child, and neither should be able to break the other.
[`Settings`](../game/settings.gd) validates every value on load and on change (volume clamped and
snapped to 10 % steps, unknown keys and mistyped values ignored), so a hand-edited file falls back
to defaults rather than failing. [`SettingsManager`](../game/managers/settings_manager.gd) applies
and saves each change at once. Sound goes through an `SFX` bus and music through a `Music` bus
(`default_bus_layout.tres`), set by SOUND and MUSIC (default 80 % and 60 %). Checked by [`tests/front_end_test.gd`](../tests/front_end_test.gd).

The HUD takes race state from the `RAC_` signals. The speed bar and the minimap are the exception:
the race screen hands them the cars, because they need positions every frame and no signal should
carry that 60 times a second.

## 11. Art direction and asset pipeline

**Style anchor: frame 04, "picture book".**

![Style anchor](mockups/style_anchor.png)

Soft, rounded, friendly shapes in warm bright colours; no hard black outlines; a near-overhead
camera, which suits top-down sprites. Generated by FLUX.1-dev at 1344 × 768, seed **202**, guidance
3.5, 20 steps, euler / beta, with the prompt:

> top-down view from directly above of a winding race track for a children's racing video game:
> grey asphalt road with red and white kerbs, green grass, a few round trees, tyre stacks and hay
> bales, four small colourful race cars (red, blue, yellow, green) driving around a bend, 2D video
> game screenshot, soft flat children's picture book illustration, rounded friendly shapes, warm
> bright flat colours, no outlines

What the frame gets right, and production assets must keep: rounded cartoon proportions, warm
saturated greens and greys, chunky red/white kerbs, props as soft simple blocks. What it gets wrong
and Phase 2 must correct: the soft 3D shading and drop shadows (FLUX's house style — the prompt
asked for flat), and the slight perspective on some cars. This image is the reference fed to
`ReduxAdvanced` when style-locking every asset.

Assets come from local ComfyUI through `tools/comfy/`:

| Asset | Count | Approach |
| --- | --- | --- |
| Player car | 1 | **Chosen: the sports car** (`mockups/raw/car_sports.png`, seed 11). Generated top-down, cut out with BiRefNet, rotated from its nose-down source to +X, fitted to 128 × 72 |
| Opponent cars | 3 | The player car repainted blue, yellow and green with FLUX Kontext — identical silhouette, proven in [`mockups/car_palette.png`](mockups/car_palette.png) |
| Ground fills | 3 | Asphalt, grass, sand — **procedural flat colour** sampled from the style anchor (the bake-off showed generated fills cannot tile) |
| Edge / corner tiles | ~16 per surface pair | Composited by script from the fills (§7.2) |
| Kerbs, finish line | 2 | Drawn — red/cream kerb strip and a chequer, both tileable |
| Props | 4 | Straw ring, hay bale, tree, tyre stack — generated + cut out, style-locked to the style board. The tyre stack's hole is punched out in post so the ground shows through |
| UI | 7 | Coin, and one card illustration per drift setup |

### 11.0 Production (Phase 3)

Every asset, its subject or edit instruction, pinned seed, facing, size and output path is in
[`tools/comfy/asset_manifest.json`](../tools/comfy/asset_manifest.json). Picks were made from four
candidates each ([`mockups/candidates/`](mockups/candidates/)); the whole set is shown together in
[`mockups/asset_overview.png`](mockups/asset_overview.png). To rebuild:

```bash
python tools/comfy/generate_assets.py build            # reuse cached masters
python tools/comfy/generate_assets.py build --force    # re-render everything from seeds
```

### 11.1 The frozen recipe (Phase 2)

Five bake-off rounds ([`mockups/bakeoff/`](mockups/bakeoff/)) settled the recipe in
[`tools/comfy/pipeline.json`](../tools/comfy/pipeline.json):

| Setting | Value | Why |
| --- | --- | --- |
| Model | FLUX.1-dev, fp8 weights | SD3.5 was faster but gritty and realistic. bf16 was not reproducible at 1536 px |
| Size | 1536 px, downscaled to sprite size | The softest, most anchor-like finish of any setting |
| Style lock | Redux on the **style board**, factor 4.5 / weight 0.75 | The full style frame leaked its track into every asset; the board is frame 04's objects only |
| Steps | 20 | 30 steps added nothing visible |
| Cut-out | BiRefNet-general | `toonout` kept shadows, filled the straw ring's hole and kept a dirt rim on trees |
| Picking | 4 candidates per asset, best one pinned | Quality over speed |

The recipe is **verified reproducible**: an identical request regenerates pixel-identically, so a
pinned seed fully defines an asset. Prompt lessons — how to get props truly top-down, and that car
facing is unreliable and must be recorded per asset — are kept in `pipeline.json` itself.

### 11.2 Sound (Phase 8)

Six sounds are generated with **Stable Audio 3** through the same ComfyUI client, declared with
prompts and pinned seeds in [`tools/comfy/sfx_manifest.json`](../tools/comfy/sfx_manifest.json) and
built by [`tools/comfy/generate_sfx.py`](../tools/comfy/generate_sfx.py) into `art/sfx/` as mono
16-bit WAVs. Recipe: `stable_audio_3_medium_base`, 50 steps, cfg 7. A bake-off on a tyre-squeal
probe found it gave the cleanest tonal squeal; `small_sfx` is distilled (cfg 1 only) and noisier.
Four candidates per sound were picked from spectrogram sheets in [`mockups/sfx/`](mockups/sfx/).
One-shots are trimmed and faded; the two loops (engine, squeal) are cut from the steadiest stretch
of their clip and cross-faded so they repeat without a click, and imported with looping on. The
countdown beeps are synthesised: a pure tone is what they need.

```bash
python tools/comfy/generate_sfx.py candidates [--only coin]   # render candidates + review sheet
python tools/comfy/generate_sfx.py pick coin 104              # pin a seed
python tools/comfy/generate_sfx.py build                      # write art/sfx/*.wav
```

## 12. Cups

A **cup** is three races in a row with points, standings and a trophy at the end.

| Cup | Races | Opens |
| --- | --- | --- |
| **Sunshine Cup** | Meadow Loop, Sunny Beach, Toy Town | from the start |
| **Snowflake Cup** | Toy Town, Meadow Loop, Snowy Peak | when the Sunshine Cup has been **won** (1st overall) |
| **Starlight Cup** | Jungle Run, Candy Lane, Moon Base | when the Snowflake Cup has been **won** |

- **Points** 10 / 7 / 5 / 3 per race, so everyone scores; a tie goes to whoever did better in the
  last race.
- **Flow:** PICK A RACE → a cup card → race → results (RACE AGAIN becomes STANDINGS) →
  standings, the points just won counting up → NEXT RACE … → after the last race PODIUM!
  ([`screenshots/cup_standings.png`](screenshots/cup_standings.png),
  [`screenshots/cup_podium.png`](screenshots/cup_podium.png)).
- **Podium:** the top three cars on a 2-1-3 podium, confetti, the fanfare, then the player's prize
  flies in: **gold / silver / bronze** trophy for 1st–3rd overall, the **ribbon** for 4th — finishing
  a cup is always celebrated, and always pays: **300 / 200 / 150 / 100** bonus coins
  (`EconomyConfig.cup_bonus`) on top of the normal per-race payout.
- **The next cup opens only on a win.** This is stricter than the tracks (which open on any
  finish) — the user's call: the cups are the goal for a child who can already win races. Easy
  difficulty (§8.3) is the route for a child who cannot yet. A trophy is never lost: a cup keeps
  the best ever won.
- **Leaving and resuming:** the progress is saved after every race, so leaving through the pause
  menu, the standings' GARAGE button or closing the game keeps the cup. The cup card then says
  CONTINUE — RACE 2 OF 3, and the title screen shows CONTINUE CUP. Starting a cup again from its
  card starts it over. A race left half-way scores nothing and is raced again.

| Piece | File |
| --- | --- |
| `CupConfig` — name, icon, tracks, points | [`game/configs/cup_config.gd`](../game/configs/cup_config.gd), `game/configs/cups/*.tres` |
| `CupManager` — phases none → racing → results → … → done, points, standings, trophy; in the shell next to `GarageManager` | [`game/managers/cup_manager.gd`](../game/managers/cup_manager.gd) |
| Standings, podium | [`ui/cup/`](../ui/cup/) |
| Cup cards on PICK A RACE | [`ui/track_select/cup_card.gd`](../ui/track_select/cup_card.gd) |
| Checks: points, ties, resume after closing the game, trophies, coins, opening on a win only, a single race not counting, and a whole cup through the real screens | [`tests/cup_test.gd`](../tests/cup_test.gd) |

`CupManager` owns the cup's logic and `GarageManager` its saving: after each race the manager
sends `CUP_progress_changed` (saved as `[cup] progress`), and at the end `CUP_finished` (cup,
standings, trophy), on which `GarageManager` pays the bonus and records the trophy in
`[trophies]`. Both sections are optional in the save, so the schema version did not change.

The art — gold trophy, ribbon, sun and snowflake icons — was generated and picked from four
candidates each; silver and bronze are Kontext recolours of the gold one, so all three trophies
share one shape. Reverse tracks (in the roadmap) were left out: four tracks gave two cups of three,
and the three themes added later (§7) make the third, the Starlight Cup, with a drawn star icon (§7.5).

## 13. Music

Every screen has music, generated like the sound (§11.2) with **Stable Audio 3**, declared in
[`tools/comfy/music_manifest.json`](../tools/comfy/music_manifest.json) and built by
[`tools/comfy/generate_music.py`](../tools/comfy/generate_music.py) into `art/music/` as stereo
Ogg Vorbis (about 6 MB in all).

| Piece | Plays on | Tempo, loop |
| --- | --- | --- |
| `menu` — ukulele, glockenspiel, whistling | title, garage, pick a race, results | 108 BPM, 16 bars after a 2-bar lead-in |
| `race_meadow` — banjo, fiddle, country pop | Meadow Loop | 132 BPM, 16 bars |
| `race_beach` — steel drums, surf guitar, calypso | Sunny Beach | 126 BPM, 16 bars |
| `race_town` — toy piano, marimba | Toy Town | 136 BPM, 16 bars |
| `race_snow` — sleigh bells, celesta, pizzicato | Snowy Peak | 128 BPM, 16 bars |
| `race_jungle` — marimba, kalimba, bongos *(synthesised)* | Jungle Run | 120 BPM, 16 bars |
| `race_candy` — music box, glockenspiel, toy organ *(synthesised)* | Candy Lane | 132 BPM, 16 bars |
| `race_moon` — synth arpeggios, square lead, lydian *(synthesised)* | Moon Base | 124 BPM, 16 bars |
| `standings` — a 3-second marimba sting, then `menu` | cup standings | once |
| `podium` — brass fanfare, timpani | cup podium (replaces the finish fanfare there) | 112 BPM, 8 bars after a 2-bar fanfare |

**Recipe.** `stable_audio_3_medium_base`, 50 steps, **cfg 6**: in a probe at 120 BPM it held the
prompted tempo exactly and had the firmest beat of the installed models; at cfg 7 two of three
seeds clipped. ACE-Step, named in the roadmap, turned out not to be installed and was not
compared. Six candidates per piece.

**Loops cut to whole bars.** The loop length starts as the prompt's `bars` at its tempo and is
refined (±0.5 %) to the lag at which the music best matches itself; the loop starts on the beat
whose surroundings sound most like the music one loop later, and is lined up to the sample across
the seam. The file keeps `intro_bars` of lead-in before the loop, and the last 60 ms before the
jump are cross-faded with the 60 ms before the loop start, so the seam is the same music both
ways. `build` writes a [`MusicPiece`](../game/configs/music_piece.gd) per piece
(`game/configs/music/*.tres`) with the stream, `loop_offset` and tempo; the game plays the file
from the top and Godot jumps back to `loop_offset` at the end. **Seam check:** the spectral jump
across the seam as played must be no larger than the music's own 95th-percentile jump from frame
to frame; `build` refuses a piece that fails. Every pick passes (0.24–0.87). Candidates are also
scored on tempo held, how well the loop matches and clipped samples; the scores and spectrograms
are on the sheets in [`mockups/music/`](mockups/music/).

**Synthesised, for the three later themes.** `race_jungle`, `race_candy` and `race_moon` were added
without ComfyUI to hand, so [`tools/comfy/synth_music.py`](../tools/comfy/synth_music.py) writes
them note by note: a four-chord progression, a bass line, drums and a lead built from the chords'
notes as a 4-bar phrase repeated A A' B A'', on small synthesised instruments (marimba, music box,
square lead and so on), levelled like the generated pieces. The 16 bars are rendered with what
rings past the end wrapped round to the start, so each loop is seamless from 0 s. They are
simpler than the generated pieces; their Stable Audio prompts are already in the manifest without
a seed (so `build` skips them), and `candidates`, `pick` and `build` replace them like any piece.

**Picked by ear.** `generate_music.py listen` writes MP3 previews of every candidate — lead-in, one
loop, then the jump back and 8 more seconds so the seam can be heard — and a page to compare them.
The picks in the manifest were made from the scores; swapping one is `pick` and `build`.

```bash
python tools/comfy/generate_music.py candidates [--only menu]   # render, cut, score, sheet
python tools/comfy/generate_music.py listen                     # previews + page to pick by ear
python tools/comfy/generate_music.py pick menu 103              # pin a seed
python tools/comfy/generate_music.py build                      # art/music/*.ogg + game/configs/music/*.tres
```

**[`MusicManager`](../game/managers/music_manager.gd)**, in the shell next to `SoundManager`:

- A screen change picks the screen's piece and cross-fades to it over a second; a piece shared by
  the next screen carries on rather than starting over. The race asks for its track theme's piece
  (`TrackTheme.music`, `UI_music_requested`).
- The 3-2-1 countdown ducks the music 10 dB under the beeps; GO brings it back.
- **Last lap** (`RAC_final_lap_started`, when the player starts it): the music speeds up 6 % —
  tempo and pitch together, about a semitone brighter.
- The finish fades the race music out, so the fanfare plays alone; the results bring the menu
  theme in.
- Pause ducks it 8 dB; it keeps playing under the pause menu.
- Under the dummy audio driver (headless) nothing plays, but `current` still follows, so the
  test can check it. Quitting fades it out first (see `main.gd`).

Checked by [`tests/music_test.gd`](../tests/music_test.gd): every piece is an Ogg stream that
loops past its lead-in on whole bars, every theme has its own race music, each screen's piece, the
menu not restarting between menu screens, ducking, last lap, finish, and the MUSIC setting on the
Music bus. Run with a window, it also checks the podium music is really playing.
[`tests/race_test.gd`](../tests/race_test.gd) checks the last lap is announced once.

## 14. Trophy shelf and stickers

Rewards a child who cannot read yet can see and collect. The **trophy button** beside PLAY on
the title opens the shelf ([`screenshots/shelf.png`](screenshots/shelf.png)): a playroom wall
with every cup's best trophy standing on a shelf over the cup's picture, and the sticker book
pinned to the wall above. Anything not won yet shows as a pale outline of itself, so the child can see what is still
to find. Moving over a prize names it, or says how to win it, for a grown-up to read out.

| Sticker | Earned by |
| --- | --- |
| **First Drift** | the first drift in a race |
| **Super Drift** | a drift of 3 seconds or more (`LONG_DRIFT_SECONDS`) |
| **First Win** | winning a race |
| **Careful Driver** | a lap with no wall hit |
| **Pile of Coins** | 200 coins or more from one race, the cup bonus included (`RICH_RACE_COINS`) |
| **Explorer** | having finished every track |
| **Car Collector** | owning every car |

The roadmap said **100** coins in one race, but a win alone pays 100, so that sticker would always
come with First Win. At 200 it takes a win on a track raced for the first time, or 2nd or better
in a cup (its bonus counts) — still reachable after every track has been finished.

- **A new sticker pops onto the screen** — [`StickerPopup`](../ui/stickers/sticker_popup.gd) in
  the shell, so it shows over any screen and carries on through a screen change. It bounces in big
  under the lap panel, above the middle of the screen (clear of the player's car), with NEW
  STICKER! ([`screenshots/sticker_popup.png`](screenshots/sticker_popup.png)), holds two seconds and shrinks away, with a pop-and-twinkle sound. Several at once (a
  win on a new track brings Pile of Coins and First Win) take turns.
- **[`StickerManager`](../game/managers/sticker_manager.gd)** in the shell decides: it watches
  the race and car signals for the player's own car (the one with a `PlayerMarker`) and only
  during a race, so the title's attract mode never earns anything, and the garage state for
  cars and tracks. It emits `PRO_sticker_earned`; `GarageManager` saves it.
- **Never twice, never lost.** The manager ignores anything already earned, the save keeps the
  list in an optional `[stickers] earned` (no schema bump), and nothing ever removes one.
- Stickers are data: a [`StickerConfig`](../game/configs/sticker_config.gd) per sticker in
  `game/configs/stickers/` (name, hint, picture); only the rules are code.

**Art.** Seven sticker pictures and the shelf wall, from four candidates each with the frozen
recipe. The white die-cut edge is not generated: `postprocess.sticker_border` grows each cut-out's
silhouette, fills its holes and puts it on white, so all seven share one edge. The wall is the
first full-screen picture through the recipe (`size` in the manifest: no cut-out, style-locked
like everything else, cropped to 1920 × 1080).

Checked by [`tests/sticker_test.gd`](../tests/sticker_test.gd): each sticker triggered, only by
the player and only in a race, exactly once, kept across closing the game; both drift stickers
with a real car's physics; a real race earning stickers; the popup queue; and the shelf from the
title showing exactly what was earned.

## 15. Two players, split screen

Racing with a parent or sibling on the same sofa. **2 PLAYERS** on the title opens the join
screen ([`screenshots/join.png`](screenshots/join.png)):

- **Joining by pressing.** Each player claims a device by pressing its button: **A** on a gamepad,
  **SPACE** for the left half of the keyboard (W A S D, Space drifts, E horn), **ENTER** for the
  right half (the arrows, Right Ctrl or Numpad 0 drifts, Right Shift horn). The first to press is
  player 1 (red), the second player 2 (purple). Any mix works: two gamepads, a gamepad and a
  keyboard half, or one keyboard shared.
- **Cars.** Each player picks from the cars the garage owns with their own left / right; player 1
  starts in the equipped car, player 2 in the next one owned, so the two look different. Each car
  wears its saved paint.
- **O / Y** switches the AI opponents off (two players alone) and on (two players and two AI).
- Pressing the join button again goes to PICK A RACE — tracks only: the cups are one child's
  progress. B goes back to the join screen, and B there (or any return to the title) ends the
  two-player game.

**[`PlayersManager`](../game/managers/players_manager.gd)** (in the shell, `PLY_` signals) holds
who plays on what, and binds each player's own actions — `p1_accelerate`, `p2_steer_left`, … — to
their device alone; [`PlayerInput`](../actors/car/player_input.gd) reads them through its
`action_prefix`. A one-player game keeps the shared actions, where every key and pad drives.

**The split** ([`screenshots/split_screen.png`](screenshots/split_screen.png)): two `SubViewport`s
side by side, left for player 1. The world — track, skid marks, cars — lives in the left one; the
right one shares its `World2D`, so it is one world seen by two cameras (player 2's chase camera
draws into the right view through `Camera2D.custom_viewport`). Each half has its player's HUD,
laid out mirrored about the middle — place on the outside edge, lap inside, speed bar in the
outside corner — with the timer left out, and one minimap sits between them at the bottom. Car
sounds are heard from player 1's view.

**The race:**

| Rule | Why |
| --- | --- |
| The players start side by side on the same grid row | neither starts ahead |
| The AI is rubber-banded to the player further behind | nobody is left racing alone |
| A player who finishes is driven on by the AI at an easy pace | their car never blocks the other |
| The race ends when both have finished, or 30 s after the first did (`LAST_PLAYER_WAIT`) | the winner is never kept waiting; the other gets an estimated time, like an opponent |
| Both places are paid into the one garage, each on its own line; a new track's bonus once | racing together still moves the family save on |
| The results name the better player: P1 WON! / P2 CAME 2ND! | always cheerful, as for one player |

Stickers can be earned by either player. **Performance:** on the development machine the split
race runs at the monitor's 100 fps (vsync), so there is no particle cut per view yet; a check on
the release machine belongs to Phase 17.

Checked by [`tests/two_player_test.gd`](../tests/two_player_test.gd): joining (a device once,
no third player, each action answering its own device only, the title ending it), the join
screen driven by key and pad events, a whole split race on autopilot (two views sharing one
world, a HUD each showing its own player's place, both players in the results and paid), and a
race with no opponents.

## 16. Time trial and ghosts

Something to come back to once the cups are won. PICK A RACE has a **RACE / TIME TRIAL** switch
above the track cards ([`screenshots/pick_a_race_time_trial.png`](screenshots/pick_a_race_time_trial.png));
in a time trial the cards show each track's record and the cups make way (a cup is always a
race). Two players have no time trial.

- **The run.** The player alone, three laps, the HUD without a place. Nothing is paid — there is
  nobody to beat but the clock — and the results list the laps with the best marked, then the
  record before and the gold ghost's time ([`screenshots/time_trial_results.png`](screenshots/time_trial_results.png)).
  The headline is NEW RECORD!, FASTER THAN GOLD! or GREAT DRIVING!; RACE AGAIN is TRY AGAIN.
- **Records.** The best lap per track, and per track *and car* (`[time_trial]` in the save:
  track = {best, setup, cars}). Lap 1 counts from GO, as the HUD's clock does, so it is rarely
  the best.
- **Ghosts** ([`screenshots/ghost_race.png`](screenshots/ghost_race.png)): two see-through cars
  set off each time the player crosses the line —
  - **gold**: the developer ghost, the autopilot at full pace in the Starter car, shipped as
    `game/configs/ghosts/<track>.res` and recorded by
    [`tools/dev/record_ghosts.tscn`](../tools/dev/record_ghosts.gd) (24.3 / 21.8 / 31.0 / 26.85 s);
  - **white**: the player's own record lap on the track, in the car and paint it was set in. A
    lap that beats it during the run becomes the ghost from the next lap on.
- **Recording.** [`GhostRecorder`](../actors/ghost/ghost_recorder.gd) samples the car on every
  physics tick from line to line, after the cars have moved: x, y and rotation as floats plus
  the draw layer as a byte (on a bridge the ghost is drawn above the deck too) — about 20 KB a
  lap. [`GhostCar`](../actors/ghost/ghost_car.gd) replays sample *k* on the *k*-th tick of the
  lap, so it is exactly where the car was; at another physics rate it blends the two nearest
  samples by time. It has no body and collides with nothing, and is drawn under the cars.
- **Files.** A record ghost is [`GhostLap.to_dict`](../game/ghost_lap.gd) written with
  `FileAccess.store_var`, which cannot hold objects, so a ghost file can never carry code; one per
  track beside the save (`user://vicky_racer_ghosts/`). A missing or broken file is simply no ghost.

Checked by [`tests/ghost_test.gd`](../tests/ghost_test.gd): the ghost data alone (samples, file
round trip, broken files, replay timing); a real time trial where the test traces the car itself
and the ghost of the best lap then drives that lap again **0.0000 px** from the trace, tick by
tick, over three laps; no coins, three laps reported, the record and the ghost saved, both
surviving a reload and the next run racing the saved ghost; and the switch on PICK A RACE.

## 17. Release build

A Windows build that starts from a desktop icon: **`VickyRacer.exe`**, one file of 125 MB with
the game inside (the pack embedded), running from any folder with no editor, ComfyUI or Python.

```bash
Godot_console.exe --path . --headless --export-release "Windows" build/windows/VickyRacer.exe
```

- **Preset** ([`export_presets.cfg`](../export_presets.cfg)): Windows x86-64, product name *Vicky
  Racer*, version **1.0.0** (`application/config/version`, also shown small on the title), the
  icon in the .exe. `tests/`, `tools/` and `docs/` are filtered out (and `tools/`, `docs/`
  are not even imported: `.gdignore`); `build/` is git-ignored. Needs the 4.7.1 export
  templates — only the Windows ones are installed here (the full set did not fit on C:).
- **Art** ([`tools/comfy/make_release_art.py`](../tools/comfy/make_release_art.py)), composed from
  approved assets, nothing newly generated: the icon is the red car racing up a road on a grass
  tile ([`art/ui/release/icon.png`](../art/ui/release/icon.png), `.ico` from 16 to 256 px); the boot
  splash is VICKY RACER in the title's font and colours over the car, shown at least 1.2 s.
- **Boot polish:** the window is titled *Vicky Racer*. The project's internal name stays
  `VickyRacer`, because it names the save folder (`%APPDATA%/Godot/app_userdata/VickyRacer`) and
  renaming it would lose every save. Fullscreen was already remembered; now the window's size
  and position are too (`window_rect` in the settings file, kept on quit and before going
  fullscreen, restored only if that spot is still on a screen).
- **Found by exporting:** Godot 4.7's export converter left the `PackedColorArray` of opponent
  colours in the track configs **empty** in the .exe (every opponent's minimap dot turned black).
  They are an `Array[Color]` now, and a probe that loads all 45 config resources in the project
  and in the exported pack finds them identical.
- **Performance** (`tests/perf_probe.gd`, now with `--track=` and `--two-player`), on the
  development machine (RTX 5070 Ti), vsync off:

  | Case | Frame (uncapped) | Simulation per frame (headless) |
  | --- | --- | --- |
  | One player, Meadow Loop | 0.54 ms | 210 µs |
  | One player, Snowy Peak (ice) | 0.54 ms | 235 µs |
  | Two players split, Snowy Peak, four cars | 0.60 ms | 232 µs |

  The busiest moment uses under 4 % of a 60 fps frame, so nothing was cut. The probe now
  removes the pause menu (a window that never had focus paused the race mid-measurement), and
  reports paused frames. On an unknown machine: `VickyRacer.exe -- --fps`.
- **Playtest:** [`PLAYTEST.md`](PLAYTEST.md) — what to check before, what to watch for per
  pillar, and what to write down after.

## 18. Out of scope for v1

Ideas parked for later are listed in
[`ROADMAP.md`](ROADMAP.md). Touch controls remain out of scope.

## 19. Free Drive: the town

**TOWN** on the title screen opens Free Drive: no race, no laps, no timer, nobody to beat. The
child drives their own car (the one equipped in the garage, in its paint) round a little town
— and the town gets on with its day around them.

![The town](screenshots/town_overview.png)

![Driving in town](screenshots/town_street.png)

| Piece | What it is | File |
| --- | --- | --- |
| Layout | A grid of 5 × 4 blocks between two-lane streets, as data: which road is left out (the park is two blocks wide), and what stands in each block | [`town/town_layout.gd`](../town/town_layout.gd) |
| Town | Builds grass, pavements, streets, zebra crossings, buildings, the park, trees and the edge in `_ready`; sets surfaces; the traffic's map | [`town/town.gd`](../town/town.gd) |
| Screen | The player's car, traffic, animals, coins, sky; shop signs and the all-places bonus | [`game/screens/town.gd`](../game/screens/town.gd) |
| Traffic | A driver child for the same `car.tscn` every racer uses | [`actors/traffic/traffic_driver.gd`](../actors/traffic/traffic_driver.gd) |
| Animals | Dogs, cats, duck families | [`actors/town/walker.gd`](../actors/town/walker.gd) |
| Sky | Cloud shadows, hot-air balloons, flocks of birds | [`actors/town/town_sky.gd`](../actors/town/town_sky.gd) |
| HUD | Coins, the town map, the shop sign | [`ui/town/`](../ui/town/) |
| Checks | Network, lanes, buildings, surfaces, a minute of traffic, coins and shops | [`tests/town_test.gd`](../tests/town_test.gd) |

### 19.1 The street view

Every building faces down the screen: its roof seen from above, its front wall below it, like a
picture-book town map. The camera never rotates (§5), so a front that faces down always faces
the viewer. Shops stand along the **bottom** edge of their block, door onto the pavement of the
road below; houses also stand along the top edge, facing their front gardens. A building's
picture is its solid wall (less a 14 px inset), so cars bump along shop fronts as along a track
wall.

| Kind | Buildings |
| --- | --- |
| Shops (with a sign) | candy shop, ice cream parlour, toy shop, bakery, pet shop, pizza place, flower shop |
| Town (with a sign) | fire station, police station, school, car wash |
| Houses | red, blue and green family houses |

### 19.2 Buildings: a sketch for Kontext

FLUX-dev draws a building **isometric**, however it is asked — "top-down RPG view", "orthographic
front view, no side walls", "flat lay" all came back at 45°
([`mockups/town/probes/01_view_search.png`](mockups/town/probes/01_view_search.png)), which cannot
stand on a top-down street grid. Image-to-image from a drawing in the right view was either
still flat (denoise 0.75) or isometric again (0.88). **FLUX Kontext** keeps the layout of the
image it edits, so each building is drawn first as a flat block sketch in the street view
(`postprocess.building_sketch`: roof colour, wall colour, width, the front — a door between
windows, garage doors, or an open counter) and Kontext turns it into the clay look, adding what
the manifest's `details` asks for: a giant lollipop on the candy shop's roof, a teddy bear on the
toy shop, a donut on the bakery, a bone on the pet shop. The manifest's buildings are ordinary
sprites with a `sketch` and `details`, so `candidates` / `pick` / `build` work as for
everything else; built pictures are trimmed to their edges, because a building is placed by
them. Kontext keeps the view but not always the sketch's width (the police station came out
narrower); that is fine, the row is spread from the built widths.

The first fire station details gave plain red sheds; asking for a bell, a coiled hose, a ladder
on the wall and "a little red fire engine peeking out of the middle door" made it read at once.
Review sheets of every round are in [`mockups/town/probes/`](mockups/town/probes/).

The town's other art is ordinary txt2img sprites (the frozen recipe, four seeds each):

| Art | Pick | Note |
| --- | --- | --- |
| Fountain, playground, bench, flower bed | 12, 12, 12, 11 | true top-down at the first try |
| Bus, fire engine, delivery van | 13, 11, 11 | all face **down** (windscreen and lights at the bottom), not the "up" asked for; the van has a face |
| Garbage truck | 12 | the first prompt gave four side views; re-asked as "only its roof visible", seed 12 is seen from above, cab to the **right** |
| Dog, cat, bird | 11, 12, 12 | most seeds drew animals standing, facing the camera; the picks are the ones seen from above (dog faces down, cat and bird up) |
| Duck | 12 | side views twice; seed 12 of the second prompt is nearest to above |
| Hot-air balloon | 11 | always drawn from the side. Kept: high in the sky the classic shape reads better than a striped circle, and it matches the buildings' street view |

Sounds (Stable Audio, the §11.2 recipe, picked from spectrograms): **quack** 101, **woof** 103,
**meow** 103 and **town ambience** 103, a breeze with birdsong looped quietly under the town.

### 19.3 Streets and traffic

Streets are a junction graph. Each road has a lane each way, driven on the **right**, 80 px from
the centre line. `Town.lane_points(a, b)` is the line from the edge of junction *a* to the
edge of *b*; `turn_points(a, b, c)` the line through *b*: straight on, or a curve between the
two lanes (a quadratic through the point where they meet — tight to the right, wide to the left).

A `TrafficDriver` steers at a point ahead on its line, as the AI racer does, and picks a road at
random at every junction (never back the way it came). Before it drives into a junction it
**reserves** it, and waits at the line until it may — one vehicle in a junction at a time, so
nothing ever crosses another's path. It slows for what is ahead in its lane: a vehicle, the
player, a duck. Held up by the player it toots after 2 s and every 4 s after; if the player has
**stopped in its lane** for 3 s, it pulls out round them when the other lane is clear for 1,300 px
and the junction is far enough off to get back in. Town driving is calm: 300–430 px/s against a
racer's 1,100, under 200 round corners. Traffic cars get tighter low-speed steering and more grip
(`steer_speed_ref` 150, `lateral_grip` 14) so they turn on the spot of a town corner and never
drift, and their engines run 12 dB quieter (`CarAudio.engine_offset_db`).

Two bugs found by the town test: a vehicle stopping for a junction braked *into reverse* below
40 px/s (the car's own reverse rule) and crept back and forth; and one creeping up to the line
could drop the last point of its lane, forget it was waiting and drive off the map. Stopping now
brakes to a standstill and lets drag hold it, and the lane's end is kept apart from the points
still to drive.

| On the streets | How many |
| --- | --- |
| Cars, every car in every paint, at random | 18 |
| Buses, delivery vans, a fire engine, a garbage truck (bigger collision boxes) | 6 |
| Dogs and cats walking round a block on the pavement | 8 |
| Mother ducks with three ducklings, to and fro across a zebra crossing | 4 |
| Hot-air balloons, cloud shadows; a flock of five birds every 14–28 s | 3, 5 |

Animals have no bodies: a car coming fast makes one hop aside (and call out — quack, woof,
meow), and a horn tooted near one makes it jump. A duck family waits at the kerb until nothing
is driving near the crossing (cars standing still are waiting for them, so they go), then
crosses with the ducklings in a line behind, and rests on the grass on the far side. Traffic
stops for every duck and duckling, and does not drive into a junction while its way out is a
crossing with ducks on it — waiting there would block the junction for everyone.

The duck rules came from the town test: a duck rested on the pavement with her ducklings still
in the road behind her (traffic stood 17 s), and a truck that had already turned into a junction
waited for ducks inside it. The test now also checks that traffic never drives over an animal
and keeps to the right-hand lane except when overtaking.

### 19.4 Things to do

- **Coins** lie about the streets (36 at a time, 2 each). Driving through one banks it at once
  (`PRO_coins_found`, saved straight away) with the coin chime; it comes back somewhere else 40 s
  later. A minute of driving earns about what a race does, and the garage's cars are still the
  thing to save up for.
- **Shops**: pulling up at a shop door pops up its sign — the building's picture and name, and
  how many kinds of place have been visited (*NEW PLACE! 4 / 11*). Visiting all eleven in one
  drive pays a bonus of 50 coins.
- **The car wash** (§19.7): drive onto its pad and the car is washed and sparkles.
- The **pond** is water you can drive through, slowly, with a splash.

Pause has RESUME, SETTINGS and GARAGE; there is nothing to restart.

### 19.6 The camera handover

Free Drive is the first screen reached straight from the title, and the title's attract-mode
race has a camera of its own. That camera was still current when the town's camera entered,
so the town's never took over: the view froze where the car started while the car drove off
it (reported in play; it never showed in screenshots taken with `--screen=town`, which skips
the title). The chase camera now makes itself current, deferred, when it is not — once the old
screen is gone. The same fix covers CONTINUE CUP from the title. Checked by
[`tests/camera_handover_test.gd`](../tests/camera_handover_test.gd) (title, TOWN, drive: the car
must still be on screen), which fails without the fix.

Two more traffic rules came from running the town test over and over (traffic picks its way
at random, so every run differs): a vehicle waiting for its turn at a junction stops with its
front 125 px before it, clear of the zebra crossing; and a duck family does not set off while
any vehicle stands on its crossing (a bus that had crept onto it behind a queue looked, to the
ducks, like a car waiting for them).

### 19.5 Surfaces

Roads and pavements are asphalt, lawns and the grass round the town are grass, and the ponds are
**water** (speed × 0.45, grip × 0.5 — a new surface in `Track.SURFACES`, light spray instead of
dust).

### 19.7 The car wash

In front of the car wash a wet blue pad with soap bubbles and two arrows pointing in reaches
from the building across the pavement and 30 px into the road — so a car keeping to its lane
passes it, and a child steering in drives onto it. The player's car on the pad emits
`CAR_washed` (traffic is never washed). Then, all from the car's own effects and sounds:

| When | What |
| --- | --- |
| At once | a burst of white foam all over the car (left behind where it was washed); soap bubbles float up the screen; the **car wash** sound — spray and swishing brushes |
| 0.9 s | the paint gleams: a bright flash on the body that settles back |
| Then | the **sparkle** chime, and four-pointed stars (drawn in code, white to pale gold) pop up all over the car, grow, twinkle and shrink — riding with it — for **25 s**, thinning out over the last 6 |

Washing again while still sparkling starts the 25 s afresh. Both sounds are Stable Audio picks
from spectrograms: `car_wash` 103 (fades out naturally, 1.75 s), `sparkle` 103 (1.0 s). The town
test drives the player onto the pad and checks the car is washed once and sparkles, and that
traffic is not.

Found while checking it: quitting within the first second of a screen (dev screenshots) left
MusicManager's fade-in tween calling into a music player the fade-out had already freed; the
tween now checks the player is still there.
